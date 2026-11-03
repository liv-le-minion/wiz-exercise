#!/bin/bash
set -eux
exec > /var/log/mongo-setup.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y gnupg curl awscli

# INTENTIONAL: outdated MongoDB 6.0 (EOL July 2025)
curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | \
  gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-6.0.list
apt-get update
apt-get install -y mongodb-org
apt-mark hold mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools

systemctl enable --now mongod

# Wait for mongod to start
for i in $(seq 1 30); do
  mongosh --quiet --eval 'db.runCommand({ping:1})' && break
  sleep 2
done

# Create users before auth is switched on
mongosh admin --quiet --eval 'db.createUser({user:"admin", pwd:"${admin_pw}", roles:["root"]})'
mongosh admin --quiet --eval 'db.createUser({user:"appuser", pwd:"${app_pw}", roles:["readWriteAnyDatabase"]})'

# Listen on all interfaces (SG limits who can reach it) + require auth
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
cat >> /etc/mongod.conf <<CONF
security:
  authorization: enabled
CONF

systemctl restart mongod
echo "MONGO SETUP COMPLETE"
