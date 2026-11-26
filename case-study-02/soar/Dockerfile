# Use the official Python 3.12 image as base
FROM python:3.12-slim

# Set the working directory inside the container
WORKDIR /app

# Install the AWS SDK for Python
RUN pip install boto3 flask

# Copy the application files into the container
COPY app.py rule_engine.py security.py ses_handler.py s3_handler.py ./

# Run app.py when the container starts
CMD ["python", "app.py"]
