
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

sudo ufw enable
sudo ufw status verbose
```
