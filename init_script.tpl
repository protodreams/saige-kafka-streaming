#!/bin/bash
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
    
yum  update -y
# yum install -y util-linux e2fsprogs
yum install git -y

# Wait for the volume to be attached
while [ ! -e /dev/nvme1n1 ]; do sleep 1; done

kafka_vol=/dev/nvme1n1

 # Create a file system on the volume if it does not have one
file -s $kafka_vol | grep -q ext4 || mkfs -t ext4 $kafka_vol
# Create a mount point
mkdir /mnt/kafka
# Mount the EBS volume
mount $kafka_vol /mnt/kafka
chown ec2-user:ec2-user /mnt/kafka
# Add an entry to /etc/fstab to mount the volume on reboot
`echo "$kafka_vol /mnt/kafka ext4 defaults,nofail 0 2" >> /etc/fstab`
              
sudo -u ec2-user  bash <<'EOF'
# install zsh 
sudo yum install -y zsh 
sudo yum install -y util-linux-user
sudo chsh -s /usr/bin/zsh ec2-user

sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

echo -e "\nalias ll='ls -la'" >> ~/.zshrc

echo -e "\nexport JAVA_HOME=/mnt/kafka/openjdk" >> ~/.zshrc

echo -e "\nexport PATH=/mnt/kafka:$PATH" >> ~/.zshrc 

source ~/.zshrc

zsh ~/.zshrc

sudo yum install -y java-21-amazon-corretto-devel

EOF

# echo "mamba create -n models -y pytorch torchvision torchaudio cudatoolkit=11.8 transformers -c pytorch -c huggingface" > /mnt/caves_of_steel/load_olma.sh



              