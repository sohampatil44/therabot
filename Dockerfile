FROM pytorch/pytorch:2.0.1-cpu

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install extra system dependencies for GUI, image processing, etc.
RUN apt-get update && apt-get install -y \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip

# Install Python packages
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy project files
COPY . /app
COPY ripeness.h5 /app/ripeness.h5

# Create non-root user
RUN useradd -m appuser
USER appuser

EXPOSE 8000
CMD ["gunicorn", "app:app", "--bind=0.0.0.0:8000"]
