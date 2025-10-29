#!/bin/bash

# ====== VARIÁVEIS ======
dataHora=$(date +%Y%m%d%H%M%S)
numeroAleatorio=$RANDOM
sufixo="${dataHora}-${numeroAleatorio}"
regiao="us-east-1"

# ====== CRIAÇÃO DOS BUCKETS S3 ======
bucketRaw="s3rawnavix-$sufixo"
bucketTrusted="s3trustednavix-$sufixo"
bucketClient="s3clientnavix-$sufixo"

echo "Criando buckets S3..."
aws s3 mb s3://$bucketRaw --region $regiao
aws s3 mb s3://$bucketTrusted --region $regiao
aws s3 mb s3://$bucketClient --region $regiao
echo "Buckets criados:"
echo " - $bucketRaw"
echo " - $bucketTrusted"
echo " - $bucketClient"
echo "============================================="

# ====== REDE ======
vpcId=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)
idSubrede=$(aws ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)

# ====== SECURITY GROUP ======
sgId=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=launch-wizard-42" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [ -z "$sgId" ]; then
    sgId=$(aws ec2 create-security-group \
        --group-name launch-wizard-42 \
        --vpc-id $vpcId \
        --description "grupo de seguranca desafio" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-042}]" \
        --query "GroupId" \
        --output text)
    echo "Security Group criado com ID: $sgId"
fi

aws ec2 authorize-security-group-ingress \
 --group-id $sgId \
 --protocol tcp \
 --port 22 \
 --cidr 0.0.0.0/0

# ====== CRIAÇÃO DA CHAVE PEM ======
nomeChavePem="minhachave-$sufixo"
aws ec2 create-key-pair \
 --key-name $nomeChavePem \
 --region $regiao \
 --query 'KeyMaterial' \
 --output text > "$nomeChavePem.pem"
chmod 400 "$nomeChavePem.pem"

# ====== SCRIPT DE INICIALIZAÇÃO ======
scriptEC2='#!/bin/bash
set -e
sudo apt update -y
sudo apt install -y curl gnupg lsb-release ca-certificates apt-transport-https software-properties-common

# ===== MySQL =====
if ! command -v mysql &> /dev/null; then
    echo "Instalando MySQL Server..."
    sudo apt install -y mysql-server
else
    echo "MySQL já instalado."
fi

# ===== Node.js =====
if ! command -v node &> /dev/null; then
    echo "Instalando Node.js..."
    sudo apt install -y nodejs npm
else
    echo "Node.js já instalado."
fi

echo "===== Instalando OpenJDK 17 na EC2 ====="
sudo apt install -y openjdk-17-jdk

# ===== Docker =====
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "Docker já instalado."
fi

# ===== Baixar imagem MySQL no Docker (sem executar container) =====
sudo docker pull mysql:latest

# ===== Usuário sysadmin =====
if ! id "sysadmin" &>/dev/null; then
    sudo useradd -m sysadmin
    echo "sysadmin:senha123" | sudo chpasswd
fi

echo "Setup concluído com sucesso!"
'

# ====== CRIAR INSTÂNCIA EC2 ======
idInstancia=$(aws ec2 run-instances \
 --image-id ami-0360c520857e3138f \
 --count 1 \
 --security-group-ids $sgId \
 --instance-type t3.small \
 --subnet-id $idSubrede \
 --key-name $nomeChavePem \
 --user-data "$scriptEC2" \
 --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
 --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=instanciaEC2Navix-$sufixo}]" \
 --query "Instances[0].InstanceId" --output text)

echo "Instância criada com ID: $idInstancia"
echo "============================================="
echo "Buckets criados:"
echo " - $bucketRaw"
echo " - $bucketTrusted"
echo " - $bucketClient"
echo "Instância EC2: $idInstancia"
echo "Chave PEM: $nomeChavePem.pem"
