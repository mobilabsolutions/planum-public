sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -i eth0 -j REDIRECT --to-port 30001
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common jq docker.io

#curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
#echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
#sudo apt update
#sudo apt install -y docker-ce

sudo systemctl enable docker.service
sudo useradd -d /home/planum planum
sudo usermod -aG docker planum
sudo su - planum
docker run -d --net="host" -v /var/run/docker.sock:/var/run/docker.sock -v /home/planum:/home/planum --name planum mobilab.azurecr.io/planum:latest
echo "done"
