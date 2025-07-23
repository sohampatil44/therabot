FROM python:3.9-slim

#setup working directory

WORKDIR /app


RUN apt-get update && apt-get install -y \
    gcc \
    build-essential \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*


COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir --retries 10 --timeout 100 --progress-bar off -r requirements.txt

 COPY . .

 EXPOSE 8000

 CMD ["gunicorn", "main:app", "--bind","0.0.0.0:8000"]