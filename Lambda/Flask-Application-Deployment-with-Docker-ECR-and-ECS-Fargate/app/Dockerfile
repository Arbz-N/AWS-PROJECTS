FROM python:3.9-slim
# Lightweight Python image — slim variant excludes unnecessary packages

WORKDIR /app
# All subsequent commands run inside /app in the container

COPY requirements.txt .
# Copy requirements first to take advantage of Docker layer caching
# If requirements.txt does not change, this layer is reused on rebuild

RUN pip install -r requirements.txt
# Install Python dependencies at build time

COPY . .
# Copy all remaining application files

EXPOSE 5000
# Flask runs on port 5000

CMD ["python", "app.py"]
# Command executed when the container starts
# CMD is a runtime instruction, unlike RUN which runs at build time