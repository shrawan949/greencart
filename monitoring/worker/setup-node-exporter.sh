
#!/bin/bash
set -euo pipefail

# ==========================================
# NODE EXPORTER INSTALLATION
# For Kubernetes workers and other EC2 nodes
# ==========================================

if [ "$EUID" -ne 0 ]; then
    echo "Run using sudo."
    exit 1
fi

echo "Installing Node Exporter..."

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

# Create node exporter user
if ! id node_exporter >/dev/null 2>&1; then
    useradd --system --no-create-home \
      --shell /sbin/nologin node_exporter
fi

# Get latest release
VERSION=$(curl -fsSL \
  https://api.github.com/repos/prometheus/node_exporter/releases/latest |
  jq -r '.tag_name | ltrimstr("v")')

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "Could not determine Node Exporter version."
    exit 1
fi

echo "Installing Node Exporter version: $VERSION"

cd /tmp

wget -q "https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-${ARCH}.tar.gz"

tar -xzf "node_exporter-${VERSION}.linux-${ARCH}.tar.gz"

install -m 0755 \
  "node_exporter-${VERSION}.linux-${ARCH}/node_exporter" \
  /usr/local/bin/node_exporter

chown node_exporter:node_exporter \
  /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl enable --now node_exporter

echo ""
echo "======================================"
echo " NODE EXPORTER INSTALLED SUCCESSFULLY"
echo "======================================"

systemctl --no-pager status node_exporter

echo ""
echo "Node Exporter metrics:"
echo "http://PRIVATE-IP:9100/metrics"

