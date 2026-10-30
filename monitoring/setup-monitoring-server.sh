
#!/bin/bash
set -euo pipefail

# ==========================================
# PROMETHEUS + GRAFANA MONITORING SERVER
# Supported: RHEL / Rocky / AlmaLinux /
# Amazon Linux 2023
# ==========================================

PROMETHEUS_USER="prometheus"
PROMETHEUS_DIR="/etc/prometheus"
PROMETHEUS_DATA="/var/lib/prometheus"
PROMETHEUS_BIN="/usr/local/bin"

echo "======================================"
echo " Installing Monitoring Server"
echo "======================================"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Run this script using sudo."
    exit 1
fi

# Install dependencies
if command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget tar gzip jq
else
    yum install -y curl wget tar gzip jq
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Create Prometheus user
if ! id "$PROMETHEUS_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home \
      --shell /sbin/nologin "$PROMETHEUS_USER"
fi

mkdir -p "$PROMETHEUS_DIR" "$PROMETHEUS_DATA"

# Get latest Prometheus release
PROM_VERSION=$(curl -fsSL \
  https://api.github.com/repos/prometheus/prometheus/releases/latest |
  jq -r '.tag_name | ltrimstr("v")')

if [ -z "$PROM_VERSION" ] || [ "$PROM_VERSION" = "null" ]; then
    echo "Could not determine Prometheus version"
    exit 1
fi

echo "Installing Prometheus version: $PROM_VERSION"

cd /tmp

wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-${ARCH}.tar.gz"

tar -xzf "prometheus-${PROM_VERSION}.linux-${ARCH}.tar.gz"

cd "prometheus-${PROM_VERSION}.linux-${ARCH}"

install -m 0755 prometheus "$PROMETHEUS_BIN/prometheus"
install -m 0755 promtool "$PROMETHEUS_BIN/promtool"

cp -r consoles "$PROMETHEUS_DIR/"
cp -r console_libraries "$PROMETHEUS_DIR/"

chown -R "$PROMETHEUS_USER:$PROMETHEUS_USER" \
    "$PROMETHEUS_DIR" "$PROMETHEUS_DATA"

chown "$PROMETHEUS_USER:$PROMETHEUS_USER" \
    "$PROMETHEUS_BIN/prometheus" "$PROMETHEUS_BIN/promtool"

# Collect worker IP addresses
echo ""
echo "Enter private IP addresses of instances to monitor."
echo "Separate multiple IPs using spaces."
read -r -p "Worker IP addresses: " NODE_IPS

if [ -z "$NODE_IPS" ]; then
    echo "At least one worker IP is required."
    exit 1
fi

# Create Prometheus configuration
cat > "$PROMETHEUS_DIR/prometheus.yml" <<EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'ec2-node-exporter'
    static_configs:
      - targets:
EOF

for IP in $NODE_IPS; do
    if [[ ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid IP address: $IP"
        exit 1
    fi
    echo "          - '${IP}:9100'" >> "$PROMETHEUS_DIR/prometheus.yml"
done

chown "$PROMETHEUS_USER:$PROMETHEUS_USER" \
    "$PROMETHEUS_DIR/prometheus.yml"

chmod 640 "$PROMETHEUS_DIR/prometheus.yml"

# Create Prometheus systemd service
cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=$PROMETHEUS_USER
Group=$PROMETHEUS_USER
Type=simple
ExecStart=$PROMETHEUS_BIN/prometheus \
  --config.file=$PROMETHEUS_DIR/prometheus.yml \
  --storage.tsdb.path=$PROMETHEUS_DATA \
  --web.listen-address=0.0.0.0:9090
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Install Grafana repository
cat > /etc/yum.repos.d/grafana.repo <<'EOF'
[grafana]
name=Grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

if command -v dnf >/dev/null 2>&1; then
    dnf install -y grafana
else
    yum install -y grafana
fi

# Configure Grafana Prometheus datasource
mkdir -p /etc/grafana/provisioning/datasources

cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
EOF

# Enable services
systemctl daemon-reload

systemctl enable --now prometheus
systemctl enable --now grafana-server

echo ""
echo "======================================"
echo " MONITORING SERVER INSTALLED"
echo "======================================"

systemctl --no-pager status prometheus
systemctl --no-pager status grafana-server

echo ""
echo "Prometheus: http://MONITORING-IP:9090"
echo "Grafana:    http://MONITORING-IP:3000"
echo ""
echo "Grafana default login:"
echo "Username: admin"
echo "Password: admin"
echo "Change password at first login."

