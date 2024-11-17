# centralized-account/lambda/process_logs/index.py
import base64
import json
import logging
import os
import gzip
from io import BytesIO

logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def handler(event, context):
    logger.info(f'Received event: {json.dumps(event)}')

    try:
        # Check if event contains records
        if not event or 'Records' not in event:
            logger.error('No Records found in event')
            logger.error(f'Event structure: {json.dumps(event)}')
            return {
                'statusCode': 400,
                'body': json.dumps('No records found in event')
            }

        for record in event['Records']:
            try:
                # Get the base64 encoded data
                kinesis_data = record['kinesis']['data']
                # Decode base64
                decoded_data = base64.b64decode(kinesis_data)

                # CloudWatch Logs data is compressed with gzip
                with BytesIO(decoded_data) as compressed_data:
                    with gzip.GzipFile(fileobj=compressed_data, mode='rb') as gz:
                        decompressed_data = gz.read().decode('utf-8')

                # Parse the JSON data
                log_data = json.loads(decompressed_data)

                # Log CloudWatch Logs metadata
                if 'logGroup' in log_data:
                    logger.info(f"Log Group: {log_data['logGroup']}")
                if 'logStream' in log_data:
                    logger.info(f"Log Stream: {log_data['logStream']}")

                # Process the actual log events
                if 'logEvents' in log_data:
                    for log_event in log_data['logEvents']:
                        logger.info(f"Log Event: {json.dumps(log_event)}")
                        # Add your custom processing logic here
                        # For example: store in database, send notifications, etc.

            except KeyError as e:
                logger.error(f'Missing key in record: {e}')
                continue
            except json.JSONDecodeError as e:
                logger.error(f'Failed to parse JSON: {e}')
                continue
            except Exception as e:
                logger.error(f'Error processing record: {str(e)}')
                continue

        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed records')
        }

    except Exception as e:
        logger.error(f'Error in handler: {str(e)}')
        raise e
