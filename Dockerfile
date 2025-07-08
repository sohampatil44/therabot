FROM python:3.9-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    python3-dev \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    gcc g++ \
    pkg-config \
    libhdf5-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip

# Copy requirements first for better caching
COPY requirements.txt /app/

# Install packages - let pip resolve dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY ripeness.h5 /app/ripeness.h5

COPY . /app

# Create non-root user
RUN useradd -m appuser
USER appuser

EXPOSE 8000

CMD ["gunicorn", "app:app", "--bind=0.0.0.0:8000"]