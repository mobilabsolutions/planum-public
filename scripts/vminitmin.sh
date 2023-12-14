sudo apt update

sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -i eth0 -j REDIRECT --to-port 30001
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo NEEDRESTART_MODE=a apt -y install iptables-persistent docker.io
sudo systemctl enable docker.service
sudo useradd -d /home/planum planum
sudo usermod -aG docker planum
sudo su - planum
docker run --net="host" -v /var/run/docker.sock:/var/run/docker.sock -v /home/planum:/home/planum --name planum mobilab.azurecr.io/planum:latest
echo "done"

