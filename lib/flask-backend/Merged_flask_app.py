from flask import Flask, request, jsonify, make_response, send_file
from flask_cors import CORS
import pandas as pd
import io
import base64
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from datetime import datetime, timedelta
import os
import logging
import shutil
from werkzeug.utils import secure_filename
import firebase_admin
from firebase_admin import credentials, firestore
import subprocess
import numpy as np
from google.api_core import exceptions
from google.api_core import retry
import json
import time
import traceback
import sys
import pytz
import re
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Table, Spacer
from reportlab.lib.styles import getSampleStyleSheet

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s IST - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('flask.log'), logging.StreamHandler()],
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Set current date and time dynamically
current_date = datetime.now(pytz.timezone('Asia/Kolkata'))

# CORS configuration: Dynamically allow the requesting origin
CORS(app, resources={r"/*": {"origins": "*", "supports_credentials": True}})

app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50MB limit
app.config['SECRET_KEY'] = os.urandom(24)
app.config['THREADS'] = 1

logger.info(f"Matplotlib backend set to: {matplotlib.get_backend()} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

def initialize_firestore():
    try:
        cred_path = os.getenv('FIREBASE_CRED_PATH', r'"C:\Users\suremdra singh\Desktop\Flutter project\airport-authority-linkage-app\lib\flask-backend\airport-authority-linkage-firebase-adminsdk-fbsvc-1c0b27201d.json"')
        if not os.path.exists(cred_path):
            logger.error(f"Firebase credential file not found at: {cred_path} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            raise FileNotFoundError(f"Credential file missing at {cred_path}")
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred, {'projectId': 'airport-authority-linkage'})
        db = firestore.client()
        logger.info(f"Firestore initialized successfully at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        return db
    except ValueError as ve:
        logger.warning(f"Firebase app already initialized: {ve} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        db = firestore.client()
        return db
    except Exception as e:
        logger.error(f"Failed to initialize Firestore: {e}\n{traceback.format_exc()} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        raise

db = initialize_firestore()

def firestore_retry(max_retries=3, initial_delay=1.0, max_delay=10.0):
    return retry.Retry(
        predicate=lambda e: isinstance(e, (exceptions.DeadlineExceeded, exceptions.GoogleAPIError)),
        initial=initial_delay,
        maximum=max_delay,
        multiplier=2.0,
        deadline=600.0
    )

def parse_excel_serial_date(serial_num, hhmm_str=None):
    if pd.isna(serial_num) or serial_num is None:
        logger.warning(f"Invalid serial date: {serial_num} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        return None
    try:
        serial_num = float(serial_num)
        if serial_num < 0 or serial_num > 1e6:
            logger.warning(f"Serial date {serial_num} out of valid range at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            return None
        base_date = datetime(1899, 12, 30)
        date = base_date + timedelta(days=serial_num)
        if hhmm_str and not pd.isna(hhmm_str):
            try:
                hhmm_str = str(hhmm_str).strip()
                hhmm_normalized = hhmm_str.replace(':', '')
                if hhmm_normalized.isdigit() and len(hhmm_normalized) == 4:
                    hours = int(hhmm_normalized[:2])
                    minutes = int(hhmm_normalized[2:])
                    if 0 <= hours <= 23 and 0 <= minutes <= 59:
                        date = date.replace(hour=hours, minute=minutes, second=0, microsecond=0)
                    else:
                        logger.warning(f"Invalid HHMM {hhmm_str}, using 00:00 at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                        date = date.replace(hour=0, minute=0, second=0, microsecond=0)
                else:
                    logger.warning(f"Non-numeric or invalid HHMM {hhmm_str}, using 00:00 at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                    date = date.replace(hour=0, minute=0, second=0, microsecond=0)
            except (ValueError, TypeError) as e:
                logger.warning(f"Failed to parse HHMM {hhmm_str}: {e}, using 00:00 at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                date = date.replace(hour=0, minute=0, second=0, microsecond=0)
        return pytz.UTC.localize(date)
    except (ValueError, TypeError) as e:
        logger.warning(f"Failed to parse serial {serial_num} or HHMM {hhmm_str}: {e} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        return None

def clean_out_of_range(df):
    for col in df.columns:
        mask = df[col].apply(lambda x: isinstance(x, (int, float)) and abs(x) > 1e10)
        df.loc[mask, col] = None
    return df

def normalize_column_name(col):
    col = str(col).strip()
    col = re.sub(r'[\s\./&]+', '_', col)
    col = re.sub(r'_+', '_', col).rstrip('_')
    departure_mappings = {
        'SL No.': 'SL_No', 'Airport Code': 'Airport_Code', 'Airport Name': 'Airport_Name',
        'Region': 'Region', 'ProfitCenter': 'Profit_Center', 'Operator Name': 'Operator_Name',
        'CA12 No.': 'CA12_No', 'Reg No.': 'Reg_No', 'Max Allup Wt': 'Max_Allup_Wt',
        'Seating Capacity': 'Seating_Capacity', 'Helicopter': 'Helicopter',
        'Aircraft Type': 'Aircraft_Type', 'Arr Date': 'Arr_Date', 'Arr GMT': 'Arr_GMT',
        'Arr Flight No.': 'Arr_Flight_No', 'Dep Location': 'Dep_Location', 'Arr Nature': 'Arr_Nature',
        'Arr GCD': 'Arr_GCD', 'Arr Sch': 'Arr_Sch', 'Arr RCS Status': 'Arr_RCS_Status',
        'Arr RCS Category': 'Arr_RCS_Category', 'Dep Date': 'Dep_Date', 'Dep GMT': 'Dep_GMT',
        'Dep Flight No.': 'Dep_Flight_No', 'Dest Location': 'Dest_Location', 'Dep Nature': 'Dep_Nature',
        'Dep GCD': 'Dep_GCD', 'Dep Sch': 'Dep_Sch', 'Dep RCS Status': 'Dep_RCS_Status',
        'Dep RCS Category': 'Dep_RCS_Category', 'Credit Facility': 'Credit_Facility',
        'Operator Type': 'Operator_Type', 'Landing': 'Landing', 'Parking': 'Parking',
        'Open Parking': 'Open_Parking', 'Housing': 'Housing', 'RNFC': 'RNFC', 'TNLC': 'TNLC',
        'Arr Watch': 'Arr_Watch', 'Dep Watch': 'Dep_Watch', 'Counter': 'Counter', 'XRay': 'XRay',
        'UDF Charge': 'UDF_Charge', 'OLD IN PAX': 'OLD_IN_PAX', 'OLD US PAX': 'OLD_US_PAX',
        'NEW IN PAX': 'NEW_IN_PAX', 'NEW US PAX': 'NEW_US_PAX', 'OLD IN RATE': 'OLD_IN_RATE',
        'OLD US RATE': 'OLD_US_RATE', 'NEW IN RATE': 'NEW_IN_RATE', 'NEW US RATE': 'NEW_US_RATE',
        'Unique Id': 'Unique_Id', 'Arr Bill Status': 'Arr_Bill_Status',
        'Dep Bill Status': 'Dep_Bill_Status', 'UDF Bill Status': 'UDF_Bill_Status'
    }
    base_mappings = {
        'Payer ID': 'Payer_ID', 'Customer Name': 'Customer_Name', 'VAN SPOC': 'VAN_SPOC',
        'CF Validity': 'CF_Validity', 'Fleet Count': 'Fleet_Count', 'Opening Balance': 'Opening_Balance',
        'Assessment': 'Assessment', 'Realisation': 'Realisation', 'Closing Balance': 'Closing_Balance',
        'SD/BG': 'SD_BG', 'Avg Monthly Assessment': 'Avg_Monthly_Assessment'
    }
    if col in departure_mappings:
        mapped_col = departure_mappings[col]
    elif col in base_mappings:
        mapped_col = base_mappings[col]
    else:
        mapped_col = col
    logger.debug(f"Normalized '{col}' to '{mapped_col}' at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
    return mapped_col

def determine_billing_status(row, charge_col, bill_status_col):
    charge = float(row.get(charge_col, 0.0))
    return 'billed' if charge > 0 else row.get(bill_status_col, 'unbilled')

def process_excel_file(file, file_type='departure', filename="upload.xlsx"):
    try:
        stream = io.BytesIO(file.read())
        if stream.read(1) == b'':
            logger.error(f"Empty file stream for {filename} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            return {"error": "Empty file stream"}
        stream.seek(0)

        try:
            excel = pd.ExcelFile(stream, engine='openpyxl')
        except Exception as e:
            logger.error(f"Failed to read Excel file {filename}: {e} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            return {"error": f"Failed to read Excel file: {str(e)}"}

        result = {}
        for sheet in excel.sheet_names:
            logger.info(f"Processing sheet: {sheet} in {filename} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            stream.seek(0)
            header_row = 2 if file_type == 'departure' else 0
            skip_rows = 0
            logger.debug(f"Using header_row={header_row} (1-based: {header_row + 1}), skip_rows={skip_rows} for {file_type} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

            raw_sheet = pd.read_excel(stream, sheet_name=sheet, engine='openpyxl', nrows=5)
            logger.debug(f"Raw first 5 rows of {sheet}:\n{raw_sheet.to_string()} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            stream.seek(0)

            df = pd.read_excel(stream, sheet_name=sheet, header=header_row, skiprows=skip_rows, engine='openpyxl')
            logger.info(f"Raw DataFrame shape for {sheet} with header row {header_row + 1}: {df.shape} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            logger.info(f"Raw first 5 rows for {sheet}:\n{df.head().to_string()} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            logger.info(f"Raw columns in {sheet}: {list(df.columns)} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

            if df.empty or df.columns.empty:
                logger.warning(f"Sheet {sheet} is empty or has no columns in {filename} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                result[sheet] = {"error": "Empty sheet or no columns detected"}
                continue

            df.columns = [normalize_column_name(col) for col in df.columns]
            logger.info(f"Normalized columns in {sheet}: {list(df.columns)} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

            required_column = 'Customer_Name' if file_type == 'base' else 'Operator_Name'
            if required_column not in df.columns:
                logger.error(f"{required_column} column not found or unmapped in sheet {sheet}. Found: {list(df.columns)} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                result[sheet] = {"error": f"{required_column} column not found or unmapped. Found: {list(df.columns)}"}
                continue

            if file_type == 'departure' and 'Arr_Bill_Status' not in df.columns:
                logger.warning(f"Arr_Bill_Status column missing in sheet {sheet}, attempting to infer at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                df['Arr_Bill_Status'] = df.apply(lambda row: determine_billing_status(row, 'Landing', 'Arr_Bill_Status'), axis=1)
            if file_type == 'departure' and 'Reg_No' not in df.columns:
                logger.warning(f"Reg_No column missing in sheet {sheet}, setting to 'Unknown' at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                df['Reg_No'] = 'Unknown'

            df = clean_out_of_range(df)
            processed_data = []
            if file_type == 'departure':
                date_columns = ['Arr_Date', 'Dep_Date']
                for col in date_columns:
                    if col in df.columns:
                        df[col] = df[col].apply(lambda x: x if pd.notna(x) and isinstance(x, (int, float)) else None)

                gmt_columns = ['Arr_GMT', 'Dep_GMT']
                for col in gmt_columns:
                    if col in df.columns:
                        df[col] = df[col].apply(lambda x: str(int(float(x))).zfill(4) if pd.notna(x) and str(x).replace('.', '').isdigit() else None)

                df['Arr_Datetime_GMT'] = df.apply(lambda row: parse_excel_serial_date(row.get('Arr_Date'), row.get('Arr_GMT')), axis=1)
                df['Dep_Datetime_GMT'] = df.apply(lambda row: parse_excel_serial_date(row.get('Dep_Date'), row.get('Dep_GMT')), axis=1)

                numeric_columns = [
                    'Max_Allup_Wt', 'Seating_Capacity', 'Landing', 'Parking', 'Open_Parking',
                    'Housing', 'RNFC', 'TNLC', 'Arr_Watch', 'Dep_Watch', 'Counter', 'XRay',
                    'UDF_Charge', 'OLD_IN_PAX', 'OLD_US_PAX', 'NEW_IN_PAX', 'NEW_US_PAX',
                    'OLD_IN_RATE', 'OLD_US_RATE', 'NEW_IN_RATE', 'NEW_US_RATE'
                ]
                for col in numeric_columns:
                    if col in df.columns:
                        df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0.0)

                df['UDF_Bill_Status'] = df.apply(lambda row: determine_billing_status(row, 'UDF_Charge', 'UDF_Bill_Status'), axis=1)
                df['Arr_Bill_Status'] = df.apply(lambda row: determine_billing_status(row, 'Landing', 'Arr_Bill_Status'), axis=1)
                df['Dep_Bill_Status'] = df.apply(lambda row: determine_billing_status(row, 'Parking', 'Dep_Bill_Status'), axis=1)

                gmt = pytz.UTC
                ist = pytz.timezone('Asia/Kolkata')
                for index, row in df.iterrows():
                    arr_gmt = row.get('Arr_Datetime_GMT')
                    dep_gmt = row.get('Dep_Datetime_GMT')
                    airtime_hours = 0.0
                    airtime_color = 'red'
                    dep_local = None
                    arr_local = None
                    linkage_status = 'Unknown'

                    if arr_gmt and dep_gmt:
                        airtime_hours = abs((dep_gmt - arr_gmt).total_seconds() / 3600)
                        airtime_color = 'green' if airtime_hours >= 14 else 'yellow' if airtime_hours >= 10 else 'red'
                        dep_local = dep_gmt.astimezone(ist)
                        arr_local = arr_gmt.astimezone(ist)
                        linkage_status = 'Same' if row.get('Dep_Location') == row.get('Dest_Location') else 'Different'
                    else:
                        logger.warning(f"Row {index} in {sheet} failed to parse: Arr_Date={row.get('Arr_Date')}, Arr_GMT={row.get('Arr_GMT')}, Dep_Date={row.get('Dep_Date')}, Dep_GMT={row.get('Dep_GMT')}, Arr_Datetime_GMT={arr_gmt}, Dep_Datetime_GMT={dep_gmt} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

                    raw_reg_no = row.get('Reg_No')
                    logger.debug(f"Row {index} in {sheet} - Raw Reg_No: '{raw_reg_no}', Type: {type(raw_reg_no)} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                    reg_no = str(raw_reg_no).strip() if pd.notna(raw_reg_no) and raw_reg_no != '' else 'Unknown'

                    processed_row = {
                        'Unique_Id': f"FLIGHT_{index}_{current_date.strftime('%Y%m%d%H%M%S')}",
                        'Arrival_GMT': arr_gmt.isoformat() if arr_gmt else "",
                        'Departure_GMT': dep_gmt.isoformat() if dep_gmt else "",
                        'Dep_Location': str(row.get('Dep_Location', '')),
                        'Dest_Location': str(row.get('Dest_Location', '')),
                        'Airport_Name': str(row.get('Airport_Name', '')),
                        'Operator_Name': str(row.get('Operator_Name', '') or 'Unknown'),
                        'Aircraft_Type': str(row.get('Aircraft_Type', '') or 'Unknown'),
                        'Reg_No': reg_no,
                        'Airtime_Hours': f"{airtime_hours:.2f}",
                        'Airtime_Color': airtime_color,
                        'Dep_Local': dep_local.isoformat() if dep_local else "",
                        'Arr_Local': arr_local.isoformat() if arr_local else "",
                        'Linkage_Status': linkage_status,
                        'Landing': float(row.get('Landing', 0.0)),
                        'Parking': float(row.get('Parking', 0.0)),
                        'Open_Parking': float(row.get('Open_Parking', 0.0)),
                        'Housing': float(row.get('Housing', 0.0)),
                        'RNFC': float(row.get('RNFC', 0.0)),
                        'TNLC': float(row.get('TNLC', 0.0)),
                        'Arr_Watch': float(row.get('Arr_Watch', 0.0)),
                        'Dep_Watch': float(row.get('Dep_Watch', 0.0)),
                        'Counter': float(row.get('Counter', 0.0)),
                        'XRay': float(row.get('XRay', 0.0)),
                        'UDF_Charge': float(row.get('UDF_Charge', 0.0)),
                        'OLD_IN_PAX': float(row.get('OLD_IN_PAX', 0.0)),
                        'OLD_US_PAX': float(row.get('OLD_US_PAX', 0.0)),
                        'NEW_IN_PAX': float(row.get('NEW_IN_PAX', 0.0)),
                        'NEW_US_PAX': float(row.get('NEW_US_PAX', 0.0)),
                        'OLD_IN_RATE': float(row.get('OLD_IN_RATE', 0.0)),
                        'OLD_US_RATE': float(row.get('OLD_US_RATE', 0.0)),
                        'NEW_IN_RATE': float(row.get('NEW_IN_RATE', 0.0)),
                        'NEW_US_RATE': float(row.get('NEW_US_RATE', 0.0)),
                        'Arr_Bill_Status': row.get('Arr_Bill_Status', 'unbilled'),
                        'Dep_Bill_Status': row.get('Dep_Bill_Status', 'unbilled'),
                        'UDF_Bill_Status': row.get('UDF_Bill_Status', 'unbilled'),
                        'file_type': file_type
                    }
                    processed_data.append(processed_row)
            else:  # base file processing
                if 'CF_Validity' in df.columns:
                    df['CF_Validity'] = df['CF_Validity'].astype(str).replace('NaT', '')
                numeric_columns = ['Opening_Balance', 'Assessment', 'Realisation', 'Closing_Balance', 'SD_BG', 'Avg Monthly Assessment']
                for col in numeric_columns:
                    if col in df.columns:
                        df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0.0)
                if 'Customer_Name' in df.columns:
                    df['Customer_Name'] = df['Customer_Name'].astype(str).replace('nan', '')
                if 'Reg_No' in df.columns:
                    df['Reg_No'] = df['Reg_No'].apply(lambda x: str(x).strip() if pd.notna(x) and x != '' else 'Unknown')
                    logger.debug(f"Base file Reg_No values: {df['Reg_No'].tolist()} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                processed_data = df.to_dict('records')

            uploaded_data = pd.DataFrame(processed_data)
            if uploaded_data.empty or uploaded_data.columns.empty:
                logger.warning(f"Processed DataFrame is empty or has no columns for sheet {sheet} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
                result[sheet] = {"error": "Processed DataFrame is empty or no columns"}
                continue

            logger.info(f"Processed DataFrame shape for {sheet}: {uploaded_data.shape} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            logger.info(f"Processed columns in {sheet}: {list(uploaded_data.columns)} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            logger.debug(f"First few rows of processed data:\n{uploaded_data.head().to_string()} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

            chart_buf_bar = io.BytesIO()
            chart_buf_pie = io.BytesIO()
            chart_base64_bar = ''
            chart_base64_pie = ''

            if file_type == 'departure' and 'Operator_Name' in uploaded_data.columns and 'Landing' in uploaded_data.columns:
                plt.figure(figsize=(10, 6))
                landings = uploaded_data.groupby('Operator_Name')['Landing'].sum().dropna()
                if not landings.empty:
                    landings.plot(kind='bar', color='skyblue')
                    plt.title(f'Total Landings by Operator - {sheet}')
                    plt.xlabel('Operator Name')
                    plt.ylabel('Total Landings')
                    plt.xticks(rotation=45, ha='right')
                    plt.tight_layout()
                    plt.savefig(chart_buf_bar, format='png')
                    plt.close()
                    chart_base64_bar = base64.b64encode(chart_buf_bar.getvalue()).decode('utf-8')

            if file_type == 'base' and 'Customer_Name' in uploaded_data.columns and 'Assessment' in uploaded_data.columns:
                plt.figure(figsize=(10, 6))
                assessments = uploaded_data.groupby('Customer_Name')['Assessment'].sum().nlargest(5).dropna()
                if not assessments.empty:
                    assessments.plot(kind='bar', color='lightgreen')
                    plt.title(f'Top 5 Customers by Assessment - {sheet}')
                    plt.xlabel('Customer Name')
                    plt.ylabel('Total Assessment')
                    plt.xticks(rotation=45, ha='right')
                    plt.tight_layout()
                    plt.savefig(chart_buf_bar, format='png')
                    plt.close()
                    chart_base64_bar = base64.b64encode(chart_buf_bar.getvalue()).decode('utf-8')

            if file_type == 'departure' and 'Aircraft_Type' in uploaded_data.columns:
                type_counts = uploaded_data['Aircraft_Type'].value_counts().head(5).dropna()
                if not type_counts.empty:
                    plt.figure(figsize=(8, 8))
                    plt.pie(type_counts.astype(float), labels=type_counts.index, autopct='%1.1f%%', startangle=90)
                    plt.title(f'Aircraft Type Distribution - {sheet}')
                    plt.axis('equal')
                    plt.tight_layout()
                    plt.savefig(chart_buf_pie, format='png')
                    plt.close()
                    chart_base64_pie = base64.b64encode(chart_buf_pie.getvalue()).decode('utf-8')

            if file_type == 'base' and 'Fleet_Count' in uploaded_data.columns:
                fleet_counts = uploaded_data['Fleet_Count'].value_counts().head(5).dropna()
                if not fleet_counts.empty:
                    plt.figure(figsize=(8, 8))
                    plt.pie(fleet_counts.astype(float), labels=fleet_counts.index, autopct='%1.1f%%', startangle=90)
                    plt.title(f'Fleet Count Distribution - {sheet}')
                    plt.axis('equal')
                    plt.tight_layout()
                    plt.savefig(chart_buf_pie, format='png')
                    plt.close()
                    chart_base64_pie = base64.b64encode(chart_buf_pie.getvalue()).decode('utf-8')

            doc_id = f"analysis_{file_type}_{sheet}_{current_date.strftime('%Y%m%d%H%M%S')}"
            data_dict = uploaded_data.to_dict(orient='records')
            for record in data_dict:
                for key, value in record.items():
                    if isinstance(value, (pd.Timestamp, datetime)):
                        record[key] = value.isoformat() if pd.notna(value) else ""
                    elif isinstance(value, pd._libs.tslibs.nattype.NaTType):
                        record[key] = ""
                    elif pd.isna(value):
                        record[key] = ""

            max_chunk_size = 900000
            chunk_size = 500
            data_chunks = [data_dict[i:i + chunk_size] for i in range(0, len(data_dict), chunk_size)]

            main_doc = {
                'sheet_name': sheet,
                'file_type': file_type,
                'columns': uploaded_data.columns.tolist(),
                'rows': [row for row in uploaded_data.fillna('').to_dict(orient='records')[:100]],
                'stats': {
                    'total_flights': len(uploaded_data) if file_type == 'departure' else 0,
                    'unique_operators': uploaded_data[required_column].nunique() if required_column in uploaded_data.columns else 0,
                    'top_operator': uploaded_data[required_column].value_counts().idxmax() if required_column in uploaded_data.columns and not uploaded_data[required_column].empty else None,
                    'avg_airtime': float(uploaded_data['Airtime_Hours'].astype(float).mean()) if file_type == 'departure' and 'Airtime_Hours' in uploaded_data.columns else 0.0,
                    'arr_billed_count': int(uploaded_data[uploaded_data['Arr_Bill_Status'] == 'billed'].shape[0]) if file_type == 'departure' and 'Arr_Bill_Status' in uploaded_data.columns else 0,
                    'dep_billed_count': int(uploaded_data[uploaded_data['Dep_Bill_Status'] == 'billed'].shape[0]) if file_type == 'departure' and 'Dep_Bill_Status' in uploaded_data.columns else 0,
                    'udf_billed_count': int(uploaded_data[uploaded_data['UDF_Bill_Status'] == 'billed'].shape[0]) if file_type == 'departure' and 'UDF_Bill_Status' in uploaded_data.columns else 0,
                    'total_landing_charges': float(uploaded_data['Landing'].sum()) if file_type == 'departure' and 'Landing' in uploaded_data.columns else 0.0,
                    'total_parking_charges': float(uploaded_data['Parking'].sum()) if file_type == 'departure' and 'Parking' in uploaded_data.columns else 0.0,
                    'total_open_parking_charges': float(uploaded_data['Open_Parking'].sum()) if file_type == 'departure' and 'Open_Parking' in uploaded_data.columns else 0.0,
                    'total_housing_charges': float(uploaded_data['Housing'].sum()) if file_type == 'departure' and 'Housing' in uploaded_data.columns else 0.0,
                    'total_rnfc_charges': float(uploaded_data['RNFC'].sum()) if file_type == 'departure' and 'RNFC' in uploaded_data.columns else 0.0,
                    'total_tnlc_charges': float(uploaded_data['TNLC'].sum()) if file_type == 'departure' and 'TNLC' in uploaded_data.columns else 0.0,
                    'total_arr_watch_charges': float(uploaded_data['Arr_Watch'].sum()) if file_type == 'departure' and 'Arr_Watch' in uploaded_data.columns else 0.0,
                    'total_dep_watch_charges': float(uploaded_data['Dep_Watch'].sum()) if file_type == 'departure' and 'Dep_Watch' in uploaded_data.columns else 0.0,
                    'total_counter_charges': float(uploaded_data['Counter'].sum()) if file_type == 'departure' and 'Counter' in uploaded_data.columns else 0.0,
                    'total_xray_charges': float(uploaded_data['XRay'].sum()) if file_type == 'departure' and 'XRay' in uploaded_data.columns else 0.0,
                    'total_udf_charges': float(uploaded_data['UDF_Charge'].sum()) if file_type == 'departure' and 'UDF_Charge' in uploaded_data.columns else 0.0,
                    'total_operators': uploaded_data[required_column].nunique() if file_type == 'base' else 0,
                    'total_assessment': float(uploaded_data['Assessment'].sum()) if file_type == 'base' and 'Assessment' in uploaded_data.columns else 0.0,
                    'total_realisation': float(uploaded_data['Realisation'].sum()) if file_type == 'base' and 'Realisation' in uploaded_data.columns else 0.0,
                    'total_closing_balance': float(uploaded_data['Closing_Balance'].sum()) if file_type == 'base' and 'Closing_Balance' in uploaded_data.columns else 0.0
                },
                'summary': uploaded_data.describe(exclude=['datetime64[ns, UTC]']).fillna('').to_dict() if not uploaded_data.empty else {},
                'chart_bar': chart_base64_bar,
                'chart_pie': chart_base64_pie,
                'formal_summary': f"The analysis of '{sheet}' shows {len(uploaded_data)} records for {file_type} data, with {uploaded_data[required_column].nunique()} {required_column.replace('_', ' ').lower()}s." if not uploaded_data.empty else "No data processed",
                'timestamp': firestore.SERVER_TIMESTAMP,
                'total_records': len(uploaded_data)
            }
            @firestore_retry()
            def set_main_doc():
                db.collection("analysis_results").document(doc_id).set(main_doc)
                logger.info(f"Successfully saved main document {doc_id} to Firestore at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

            set_main_doc()

            for i, chunk in enumerate(data_chunks):
                sub_doc_id = f"data_chunk_{i}"
                @firestore_retry()
                def set_data_chunk():
                    db.collection("analysis_results").document(doc_id).collection("data").document(sub_doc_id).set({'records': chunk})
                    logger.info(f"Successfully saved data chunk {sub_doc_id} for {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

                set_data_chunk()

            result[sheet] = {
                'sheet_name': sheet,
                'columns': [str(col) for col in uploaded_data.columns.tolist()],
                'rows': [{str(k): str(v) for k, v in row.items()} for row in uploaded_data.fillna('').to_dict(orient='records')[:100]],
                'stats': {str(k): str(v) for k, v in main_doc['stats'].items()},
                'summary': {str(k): str(v) for k, v in main_doc['summary'].items()} if main_doc['summary'] else {},
                'chart_bar': chart_base64_bar,
                'chart_pie': chart_base64_pie,
                'formal_summary': main_doc['formal_summary'],
                'doc_id': doc_id
            }

        return result
    except Exception as e:
        logger.error(f"Error processing file {filename} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {e}\n{traceback.format_exc()}")
        return {"error": str(e), "details": traceback.format_exc()}
    finally:
        for buf_name in ['chart_buf_bar', 'chart_buf_pie', 'stream']:
            buf = locals().get(buf_name)
            if buf and hasattr(buf, 'close'):
                buf.close()
        plt.close('all')

@app.route('/upload', methods=['POST', 'OPTIONS'])
def upload():
    if request.method == 'OPTIONS':
        response = make_response('', 204)
        origin = request.headers.get('Origin')
        logger.debug(f"OPTIONS request origin: {origin} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        return response

    departure_file = request.files.get('departure_file')
    logger.debug(f"Received file for /upload: departure={departure_file.filename if departure_file else 'None'} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

    if not departure_file or not departure_file.filename or not departure_file.filename.lower().endswith(('.xlsx', '.xls')):
        logger.error(f"No valid departure file provided in /upload request at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response = make_response(jsonify({'success': False, 'error': 'Valid departure Excel file is required'}), 400)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response
    
    try:
        result = process_excel_file(departure_file, file_type='departure', filename=departure_file.filename)
        if any('error' in sheet_data for sheet_data in result.values()):
            logger.error(f"Departure file processing failed with errors: {result} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({'success': False, 'sheets': result}), 400)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        doc_id = next(iter(result.values()))['doc_id']
        logger.info(f"Upload successful with doc_id: {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response = make_response(jsonify({'success': True, 'doc_id': doc_id, 'sheets': result}), 200)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response
    
    except Exception as e:
        logger.error(f"Error in /upload at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {str(e)}\n{traceback.format_exc()}")
        response = make_response(jsonify({'success': False, 'error': str(e), 'details': traceback.format_exc()}), 500)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response

@app.route('/analyze', methods=['POST', 'OPTIONS'])
def analyze():
    if request.method == 'OPTIONS':
        response = make_response('', 204)
        origin = request.headers.get('Origin')
        logger.debug(f"OPTIONS request origin: {origin} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        return response

    base_file = request.files.get('base_file')
    logger.debug(f"Received file for /analyze: base={base_file.filename if base_file else 'None'} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")

    if not base_file or not base_file.filename or not base_file.filename.lower().endswith(('.xlsx', '.xls')):
        logger.error(f"No valid base file provided in /analyze request at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response = make_response(jsonify({'success': False, 'error': 'Valid base Excel file is required'}), 400)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response

    try:
        result = process_excel_file(base_file, file_type='base', filename=base_file.filename)
        if any('error' in sheet_data for sheet_data in result.values()):
            logger.error(f"Base file processing failed with errors: {result} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({'success': False, 'sheets': result}), 400)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        doc_id = next(iter(result.values()))['doc_id']
        logger.info(f"Analysis successful for {base_file.filename} with doc_id: {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response = make_response(jsonify({'success': True, 'doc_id': doc_id, 'sheets': result}), 200)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response
    except Exception as e:
        logger.error(f"Error in /analyze at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {str(e)}\n{traceback.format_exc()}")
        response = make_response(jsonify({'success': False, 'error': str(e), 'details': traceback.format_exc()}), 500)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response

@app.route('/search', methods=['GET', 'OPTIONS'])
def search():
    if request.method == 'OPTIONS':
        response = make_response('', 204)
        origin = request.headers.get('Origin')
        logger.debug(f"OPTIONS request origin: {origin} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        return response

    try:
        query = request.args.get('query', '').lower()
        doc_id = request.args.get('doc_id')
        page = int(request.args.get('page', '0'))
        limit = int(request.args.get('limit', '100'))
        if not doc_id:
            logger.error(f"No doc_id provided in /search request at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({"error": "doc_id is required"}), 400)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        collection = db.collection("analysis_results").document(doc_id).collection("data")
        docs = collection.get()
        if not docs:
            logger.warning(f"No data found for doc_id {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({"error": f"No data found for doc_id {doc_id}"}), 404)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        results = []
        for doc in docs:
            data = doc.to_dict().get('records', [])
            for row in data:
                reg_no = str(row.get('Reg_No', '')).lower()
                arr_local = row.get('Arr_Local')
                arr_date = 'Unknown'
                if arr_local and isinstance(arr_local, str):
                    try:
                        arr_date = datetime.fromisoformat(arr_local.replace(' IST', '')).strftime('%Y-%m-%d')
                    except ValueError:
                        arr_date = 'Unknown'
                
                airport_name = str(row.get('Airport_Name', '')).lower()
                operator_name = str(row.get('Operator_Name', '')).lower()
                aircraft_type = str(row.get('Aircraft_Type', '')).lower()

                if query and not (query in reg_no or query in arr_date.lower() or query in airport_name or query in operator_name or query in aircraft_type):
                    continue
                
                results.append({
                    'Reg_No': reg_no,
                    'Arr_Date': arr_date,
                    'Airport_Name': row.get('Airport_Name', 'N/A'),
                    'Operator_Name': row.get('Operator_Name', 'Unknown'),
                    'Aircraft_Type': row.get('Aircraft_Type', 'Unknown'),
                    'Count': 1,
                    'Unique_Id': row.get('Unique_Id', 'N/A'),
                    'Airtime_Hours': row.get('Airtime_Hours', '0.00'),
                    'Linkage_Status': row.get('Linkage_Status', 'Unknown'),
                    'Arr_Bill_Status': row.get('Arr_Bill_Status', 'unbilled'),
                    'Dep_Bill_Status': row.get('Dep_Bill_Status', 'unbilled'),
                    'UDF_Bill_Status': row.get('UDF_Bill_Status', 'unbilled'),
                    'Landing': f"₹{float(row.get('Landing', 0.0)):.2f}",
                    'UDF_Charge': f"₹{float(row.get('UDF_Charge', 0.0)):.2f}"
                })

        # Apply pagination
        start_idx = page * limit
        end_idx = start_idx + limit
        paginated_results = results[start_idx:end_idx]

        logger.info(f"Search results for query '{query}' and doc_id {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {len(paginated_results)} records")
        response = make_response(jsonify(paginated_results), 200)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response
    except Exception as e:
        logger.error(f"Error in /search at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {str(e)}\n{traceback.format_exc()}")
        response = make_response(jsonify({"error": str(e), "details": traceback.format_exc()}), 500)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response

@app.route('/stats', methods=['GET', 'OPTIONS'])
def stats():
    if request.method == 'OPTIONS':
        response = make_response('', 204)
        origin = request.headers.get('Origin')
        logger.debug(f"OPTIONS request origin: {origin} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        return response

    try:
        doc_id = request.args.get('doc_id')
        group_by = request.args.get('group_by', 'operator').lower()
        if not doc_id:
            logger.error(f"No doc_id provided in /stats request at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({"error": "doc_id is required"}), 400)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        collection = db.collection("analysis_results").document(doc_id).collection("data")
        docs = collection.get()
        if not docs:
            logger.warning(f"No data found for doc_id {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({"error": f"No data found for doc_id {doc_id}"}), 404)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        stats_summary = []
        if group_by == 'operator':
            operator_stats = {}
            for doc in docs:
                data = doc.to_dict().get('records', [])
                for row in data:
                    if row.get('file_type') != 'departure':
                        continue
                    operator = row.get('Operator_Name', 'Unknown')
                    operator_stats.setdefault(operator, {
                        'Operator_Name': operator,
                        'Region': row.get('Dep_Location', 'N/A'),
                        'Flight_Count': 0,
                        'Avg_Airtime_Hours': 0.0,
                        'Total_Hours': 0.0,
                        'Same_Linkage_Count': 0,
                        'Different_Linkage_Count': 0,
                        'Arr_Billed_Count': 0,
                        'Arr_UnBilled_Count': 0,
                        'Dep_Billed_Count': 0,
                        'Dep_UnBilled_Count': 0,
                        'UDF_Billed_Count': 0,
                        'UDF_UnBilled_Count': 0,
                        'Total_Landing_Charges': 0.0,
                        'Total_UDF_Charges': 0.0
                    })
                    operator_stats[operator]['Flight_Count'] += 1
                    airtime = float(row.get('Airtime_Hours', 0.0)) if row.get('Airtime_Hours') else 0.0
                    operator_stats[operator]['Avg_Airtime_Hours'] += airtime
                    arr_gmt = row.get('Arr_Datetime_GMT')
                    dep_gmt = row.get('Dep_Datetime_GMT')
                    if arr_gmt and dep_gmt:
                        airtime_hours = max(0, (dep_gmt - arr_gmt).total_seconds() / 3600)
                        operator_stats[operator]['Total_Hours'] += airtime_hours
                    operator_stats[operator]['Same_Linkage_Count'] += 1 if row.get('Linkage_Status') == 'Same' else 0
                    operator_stats[operator]['Different_Linkage_Count'] += 1 if row.get('Linkage_Status') == 'Different' else 0
                    operator_stats[operator]['Arr_Billed_Count'] += 1 if row.get('Arr_Bill_Status') == 'billed' else 0
                    operator_stats[operator]['Arr_UnBilled_Count'] += 1 if row.get('Arr_Bill_Status') == 'unbilled' else 0
                    operator_stats[operator]['Dep_Billed_Count'] += 1 if row.get('Dep_Bill_Status') == 'billed' else 0
                    operator_stats[operator]['Dep_UnBilled_Count'] += 1 if row.get('Dep_Bill_Status') == 'unbilled' else 0
                    operator_stats[operator]['UDF_Billed_Count'] += 1 if row.get('UDF_Bill_Status') == 'billed' else 0
                    operator_stats[operator]['UDF_UnBilled_Count'] += 1 if row.get('UDF_Bill_Status') == 'unbilled' else 0
                    operator_stats[operator]['Total_Landing_Charges'] += float(row.get('Landing', 0.0))
                    operator_stats[operator]['Total_UDF_Charges'] += float(row.get('UDF_Charge', 0.0))

            for operator in operator_stats:
                flight_count = operator_stats[operator]['Flight_Count']
                if flight_count > 0:
                    operator_stats[operator]['Avg_Airtime_Hours'] /= flight_count
                stats_summary.append(operator_stats[operator])

        elif group_by == 'airport':
            airport_stats = {}
            for doc in docs:
                data = doc.to_dict().get('records', [])
                for row in data:
                    if row.get('file_type') != 'departure':
                        continue
                    airport = row.get('Airport_Name', 'Unknown')
                    airport_stats.setdefault(airport, {
                        'Airport_Name': airport,
                        'Flight_Count': 0,
                        'Total_Landing_Charges': 0.0,
                        'Total_UDF_Charges': 0.0
                    })
                    airport_stats[airport]['Flight_Count'] += 1
                    airport_stats[airport]['Total_Landing_Charges'] += float(row.get('Landing', 0.0))
                    airport_stats[airport]['Total_UDF_Charges'] += float(row.get('UDF_Charge', 0.0))
            stats_summary = list(airport_stats.values())

        logger.info(f"Stats summary for group_by '{group_by}' and doc_id {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {len(stats_summary)} records")
        response = make_response(jsonify(stats_summary), 200)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response
    except Exception as e:
        logger.error(f"Error in /stats at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {str(e)}\n{traceback.format_exc()}")
        response = make_response(jsonify({"error": str(e), "details": traceback.format_exc()}), 500)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response

@app.route('/download_dashboard_pdf', methods=['GET', 'OPTIONS'])
def download_dashboard_pdf():
    if request.method == 'OPTIONS':
        response = make_response('', 204)
        origin = request.headers.get('Origin')
        logger.debug(f"OPTIONS request origin: {origin} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        return response

    try:
        doc_id = request.args.get('doc_id')
        if not doc_id:
            logger.error(f"No doc_id provided in /download_dashboard_pdf request at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({"error": "doc_id is required"}), 400)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        # Fetch main document from Firestore
        doc_ref = db.collection("analysis_results").document(doc_id)
        doc = doc_ref.get()
        if not doc.exists:
            logger.warning(f"No data found for doc_id {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
            response = make_response(jsonify({"error": f"No data found for doc_id {doc_id}"}), 404)
            origin = request.headers.get('Origin')
            response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
            return response

        data = doc.to_dict()
        sheet_name = data.get('sheet_name', 'Unknown Sheet')
        file_type = data.get('file_type', 'departure')
        stats = data.get('stats', {})
        formal_summary = data.get('formal_summary', 'No summary available')
        chart_bar = data.get('chart_bar', '')
        chart_pie = data.get('chart_pie', '')

        # Create a PDF buffer
        pdf_buffer = io.BytesIO()
        doc = SimpleDocTemplate(pdf_buffer, pagesize=letter)
        styles = getSampleStyleSheet()
        elements = []

        # Add title
        elements.append(Paragraph(f"{sheet_name} Dashboard Report", styles['Title']))
        elements.append(Spacer(1, 12))
        elements.append(Paragraph(f"Generated on: {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}", styles['Normal']))
        elements.append(Spacer(1, 12))

        # Add summary
        elements.append(Paragraph("Summary", styles['Heading1']))
        elements.append(Spacer(1, 6))
        elements.append(Paragraph(formal_summary, styles['BodyText']))
        elements.append(Spacer(1, 12))

        # Add stats table
        table_data = [['Statistic', 'Value']]
        for key, value in stats.items():
            table_data.append([key.replace('_', ' ').title(), str(value)])
        table = Table(table_data)
        table.setStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 12),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
            ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
            ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
            ('FONTSIZE', (0, 1), (-1, -1), 10),
            ('GRID', (0, 0), (-1, -1), 1, colors.black)
        ])
        elements.append(table)
        elements.append(Spacer(1, 12))

        # Add charts if available
        if chart_bar:
            elements.append(Paragraph("Bar Chart", styles['Heading2']))
            elements.append(Spacer(1, 6))
            # Placeholder for bar chart image
            elements.append(Paragraph("Bar Chart Image Placeholder", styles['BodyText']))
            elements.append(Spacer(1, 12))

        if chart_pie:
            elements.append(Paragraph("Pie Chart", styles['Heading2']))
            elements.append(Spacer(1, 6))
            # Placeholder for pie chart image
            elements.append(Paragraph("Pie Chart Image Placeholder", styles['BodyText']))
            elements.append(Spacer(1, 12))

        # Build the PDF
        doc.build(elements)
        pdf_buffer.seek(0)

        response = send_file(
            pdf_buffer,
            as_attachment=True,
            download_name=f"dashboard_{doc_id}.pdf",
            mimetype='application/pdf'
        )
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        logger.info(f"PDF generated and sent for doc_id {doc_id} at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}")
        return response

    except Exception as e:
        logger.error(f"Error in /download_dashboard_pdf at {current_date.strftime('%Y-%m-%d %H:%M:%S IST')}: {str(e)}\n{traceback.format_exc()}")
        response = make_response(jsonify({"error": str(e), "details": traceback.format_exc()}), 500)
        origin = request.headers.get('Origin')
        response.headers['Access-Control-Allow-Origin'] = origin if origin else '*'
        return response

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5003)  # Changed to port 5003 to match your frontend's target