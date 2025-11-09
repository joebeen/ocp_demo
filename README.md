# ocp_demo

## Notizen zu Seminar Grundlagen der Virtualisierung

### 1) Voraussetzungen (Linux + KVM)

#### Hardware (für OpenShift Local):

CPU mit VT-x/AMD-V + Nested Virtualization
≥ 4 vCPU, ≥ 16 GB RAM frei (besser 20 GB), ≥ 45 GB Disk frei

Pakete (Beispiel Ubuntu/Rocky):
##### Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virt-install libguestfs-tools \
  network-manager make git curl podman
sudo usermod -aG libvirt,libvirt-qemu $USER

##### Rocky/Alma/RHEL
sudo dnf install -y @virtualization libvirt-daemon-config-network virt-install qemu-kvm \
  libguestfs-tools NetworkManager make git curl podman
sudo usermod -aG libvirt $USER


#### Nested Virtualization prüfen/aktivieren (Host ist selbst eine VM):

##### Intel
cat /sys/module/kvm_intel/parameters/nested
##### AMD
cat /sys/module/kvm_amd/parameters/nested
##### falls "N" -> Modul neu laden (Beispiel Intel):
echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf
sudo modprobe -r kvm_intel && sudo modprobe kvm_intel

### 2) OpenShift Local (CRC) installieren & starten

#### Download & Setup
Besorge dir „OpenShift Local“ (früher crc) und die pull-secret von Red Hat (Developer-Account).

##### Binärdatei ins PATH legen, z.B. ~/bin/oc/bin
chmod +x crc
crc version


#### Konfigurieren (Ressourcen & Netzwerk)

crc config set memory 16384
crc config set cpus 6
crc config set disk-size 60
##### Optional: feste Pull-Secret-Datei
crc config set pull-secret-file $HOME/pull-secret.txt


#### Cluster starten

crc start
##### Ausgabe zeigt: oc-Login, kubeadmin-Passwort, API/Console-URLs
crc console --credentials
eval $(crc oc-env)   # oc ins PATH/Sessionsetup bringen


#### Login als kubeadmin

oc login -u kubeadmin -p '<PASSWORD_AUS_crc_console_credentials>' https://api.crc.testing:6443
oc whoami


Webkonsole: crc console (öffnet Browser).

### 3) Demo-Projekt anlegen
oc new-project demo-sqlite
oc project demo-sqlite

### 4) Minimal-App (Flask + SQLite, 1 Replica, PVC)

Wir bauen das Image in OpenShift via Binary-Build – kein externer Registry-Push nötig.

##### 4.1 Verzeichnis mit App anlegen (lokal)

Erstelle die folgenden Dateien in einem leeren Ordner (z. B. demo-sqlite-app/):

app.py
```
from flask import Flask, request, jsonify
import sqlite3, os

DB_PATH = os.environ.get("SQLITE_PATH", "/data/app.db")
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT)")
    return conn

app = Flask(__name__)

@app.route("/")
def health():
    return "OK", 200

@app.route("/notes", methods=["GET", "POST"])
def notes():
    conn = get_conn()
    if request.method == "POST":
        txt = request.json.get("text", "")
        conn.execute("INSERT INTO notes(text) VALUES(?)", (txt,))
        conn.commit()
    cur = conn.execute("SELECT id, text FROM notes ORDER BY id DESC")
    return jsonify([{"id": r[0], "text": r[1]} for r in cur.fetchall()])

```

requirements.txt

```
flask==3.0.3

```

#### Dockerfile (OpenShift-freundliche Rechte!)

##### UBI9 + Python

```
FROM registry.access.redhat.com/ubi9/python-311:latest

```
##### Arbeitsverzeichnis

```
WORKDIR /opt/app

```

##### Abhängigkeiten

```
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

```
#### App-Code

```
COPY app.py .

```

#### Schreibbares Datenverzeichnis für SQLite:
#####  - Gruppe 0 (root) und g+rwX, sodass OpenShift's random UID (mit fsGroup 0) schreiben darf

```
RUN mkdir -p /data && chgrp -R 0 /data /opt/app && chmod -R g+rwX /data /opt/app

ENV FLASK_RUN_HOST=0.0.0.0 \
    FLASK_RUN_PORT=8080 \
    PORT=8080 \
    SQLITE_PATH=/data/app.db

EXPOSE 8080
CMD ["python", "app.py"]

```

Optional .gitignore

```
__pycache__/
*.pyc

```

##### 4.2 Build in OpenShift aus lokalem Ordner
##### ImageStream + Binary BuildConfig (Docker-Strategy)

```
oc new-build --name demo-sqlite-image --binary --strategy docker

```

##### ersten Build mit lokalem Inhalt starten:

```
oc start-build demo-sqlite-image --from-dir=. --follow

```
##### 4.3 Ressourcen (PVC, Deployment, Service, Route) anwenden

Speichere als k8s.yaml:

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-sqlite-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-sqlite
spec:
  replicas: 1   # SQLite: nur EIN Writer -> bei 1 Replica bleiben
  selector:
    matchLabels:
      app: demo-sqlite
  template:
    metadata:
      labels:
        app: demo-sqlite
    spec:
      # OpenShift: Random UID; mit fsGroup:0 bekommen wir Gruppenrechte auf /data
      securityContext:
        fsGroup: 0
      containers:
        - name: app
          image: image-registry.openshift-image-registry.svc:5000/demo-sqlite/demo-sqlite-image:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: SQLITE_PATH
              value: /data/app.db
          volumeMounts:
            - name: data
              mountPath: /data
          readinessProbe:
            httpGet: { path: "/", port: http }
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: "/", port: http }
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: demo-sqlite-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: demo-sqlite-svc
spec:
  selector:
    app: demo-sqlite
  ports:
    - name: http
      port: 8080
      targetPort: http
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: demo-sqlite
spec:
  to:
    kind: Service
    name: demo-sqlite-svc
  port:
    targetPort: http
  tls:
    termination: edge

```

Anwenden:

```
oc apply -f k8s.yaml
oc rollout status deploy/demo-sqlite
oc get route demo-sqlite -o jsonpath='{.spec.host}{"\n"}'

```

Testen:

```
ROUTE=$(oc get route demo-sqlite -o jsonpath='{.spec.host}')
curl https://$ROUTE/           # -> OK
curl -X POST -H 'Content-Type: application/json' \
     -d '{"text":"Hallo OpenShift+SQLite"}' https://$ROUTE/notes
curl https://$ROUTE/notes

```

Der Inhalt liegt dauerhaft auf dem PVC. Ein Pod-Neustart überlebt die Daten.

#### 5) Nützliche Admin-Kommandos
# Logs & Pod

```
oc get pods -l app=demo-sqlite
oc logs -f deploy/demo-sqlite
oc rsh deploy/demo-sqlite -- ls -l /data

```
#### Rebuild nach Codeänderung:

```
oc start-build demo-sqlite-image --from-dir=. --follow
oc rollout restart deploy/demo-sqlite

```

#### Aufräumen:

```
oc delete project demo-sqlite

```
#### 6) Hinweise & Best Practices für SQLite auf OpenShift

Single-Replica (replicas: 1). SQLite ist dateibasiert und kein Multi-Writer-DBMS.

PVC mit RWO reicht.

Rechte/UIDs: In OpenShift laufen Container standardmäßig mit random non-root UID.

Im Dockerfile chgrp 0 + chmod g+rwX auf /data (und App-Pfad) setzen.

Im Deployment fsGroup: 0, damit die random UID Gruppenzugriff hat.

Scaling: Wenn du skalieren willst, nimm eine Server-DB (Postgres/MariaDB) oder nutze SQLite nur als Cache/Edge-State.

Wenn du magst, passe ich dir das Beispiel noch auf Node.js, FastAPI, Quarkus oder .NET an – oder erweitere es um Health-Dashboards, Swagger/OpenAPI und CI/CD (GitLab) für dein Seminar.
