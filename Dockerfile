FROM registry.access.redhat.com/ubi9/python-311:latest
USER root
RUN mkdir -p /ocp && chmod 777 /ocp
RUN mkdir -p /ocp/app && chmod 777 /ocp/app
RUN mkdir -p /ocp/data && chmod 777 /ocp/data
USER 1001
WORKDIR /ocp/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# RUN chgrp -R 0 /ocp/data /ocp/app && chmod -R g+rwX /ocp/data /ocp/app

ENV FLASK_RUN_HOST=0.0.0.0 \
    FLASK_RUN_PORT=8080 \
    PORT=8080 \
    SQLITE_PATH=/ocp/data/app.db

EXPOSE 8080
CMD ["python", "app.py"]

