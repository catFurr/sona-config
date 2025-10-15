
### Firewall configuration

```bash
sudo ufw disable
sudo ufw reset

sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 5222/tcp  # prosody
sudo ufw allow 5432/tcp  # postgres
sudo ufw allow 8443/tcp  # studio
sudo ufw allow 10000/udp  # jvb

sudo ufw enable
sudo ufw status verbose
```

### TCP connection tuning to detect dead participants

Add to /etc/sysctl.conf

```
# OS TCP keepalive (moderate)
net.ipv4.tcp_keepalive_time=15
net.ipv4.tcp_keepalive_intvl=5
net.ipv4.tcp_keepalive_probes=3
```
