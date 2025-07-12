FROM python:3.9-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    make \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    libgl1-mesa-glx \
    python3-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Install PyTorch first
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Install common packages that might be in your requirements
RUN pip install flask gunicorn numpy pandas pillow opencv-python-headless scikit-learn matplotlib seaborn

# Copy requirements and try to install remaining packages
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt || echo "Some packages failed to install"

# Copy project files
COPY . /app
COPY ripeness.h5 /app/ripeness.h5

# Create non-root user
RUN useradd -m appuser
USER appuser

EXPOSE 8000
CMD ["gunicorn", "app:app", "--bind=0.0.0.0:8000"]