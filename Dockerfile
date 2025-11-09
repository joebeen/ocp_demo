FROM registry.access.redhat.com/ubi9/python-311:latest
WORKDIR /opt/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN mkdir -p /data && chgrp -R 0 /data /opt/app && chmod -R g+rwX /data /opt/app

ENV FLASK_RUN_HOST=0.0.0.0 \
    FLASK_RUN_PORT=8080 \
    PORT=8080 \
    SQLITE_PATH=/data/app.db

EXPOSE 8080
CMD ["python", "app.py"]

