!# /usr/bin/env zsh

sudo yum install -y zsh
sudo yum install -y util-linux-user
sudo chsh -s /usr/bin/zsh ec2-user

sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

echo -e "\nalias ll='ls -la'" >> ~/.zshrc
echo -e "\nexport JAVA_HOME=/mnt/kafka/jdk-21.0.2" >> ~/.zshrc
echo -e "\nexport PATH=/mnt/kafka/kafka_2.13-3.7.0/bin:$PATH" >> ~/.zshrc 
echo -e "\nexport PATH=/mnt/kafka/jdk-21.0.2/bin:$PATH" >> ~/.zshrc 

source ~/.zshrc

zsh ~/.zshrc
