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
vpcId=$(aws ec2 describe-vpcs --region $regiao --query "Vpcs[0].VpcId" --output text)
idSubrede=$(aws ec2 describe-subnets --region $regiao --query "Subnets[0].SubnetId" --output text)

# ====== SECURITY GROUP ======
sgId=$(aws ec2 describe-security-groups \
    --region $regiao \
    --filters "Name=group-name,Values=launch-wizard-42" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [ "$sgId" == "None" ] || [ -z "$sgId" ]; then
    sgId=$(aws ec2 create-security-group \
        --region $regiao \
        --group-name launch-wizard-42 \
        --vpc-id $vpcId \
        --description "grupo de seguranca desafio" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-042}]" \
        --query "GroupId" \
        --output text)
    echo "Security Group criado com ID: $sgId"
fi

for porta in 22 80 8080 3306 3333; do
  aws ec2 authorize-security-group-ingress \
   --region $regiao \
   --group-id $sgId \
   --protocol tcp \
   --port $porta \
   --cidr 0.0.0.0/0 || true
done

# ====== CRIAÇÃO DA CHAVE PEM ======
nomeChavePem="minhachave-$sufixo"
aws ec2 create-key-pair \
 --region $regiao \
 --key-name $nomeChavePem \
 --query 'KeyMaterial' \
 --output text > "$nomeChavePem.pem"
chmod 400 "$nomeChavePem.pem"

# ====== SCRIPT DE INICIALIZAÇÃO (SOFTWARE) ======
scriptEC2='
#!/bin/bash
set -e
echo "Atualizando pacotes do sistema..."
sudo apt update -y
echo "Pacotes atualizados."

echo "Instalando dependências..."
sudo apt install -y curl gnupg lsb-release ca-certificates apt-transport-https software-properties-common
echo "Dependências instaladas."

# ===== Docker =====
echo "Verificando se o Docker está instalado..."
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    echo "Docker instalado e iniciado."
else
    echo "Docker já instalado."
fi

# ===== Usuário sysadmin =====
echo "Verificando se o usuário sysadmin existe..."
if ! id "sysadmin" &>/dev/null; then
    echo "Usuário sysadmin não encontrado. Criando o usuário..."
    sudo useradd -m sysadmin
    echo "sysadmin:senha123" | sudo chpasswd
    echo "Usuário sysadmin criado e senha definida."
else
    echo "Usuário sysadmin já existe."
fi

echo "Setup concluído com sucesso!"
'

# ====== CRIAR INSTÂNCIA EC2 ======
idInstancia=$(aws ec2 run-instances \
 --region $regiao \
 --image-id ami-0360c520857e3138f \
 --count 1 \
 --security-group-ids $sgId \
 --instance-type t3.small \
 --subnet-id $idSubrede \
 --key-name $nomeChavePem \
 --user-data "$scriptEC2" \
 --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
 --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=NavixServer-$sufixo}]" \
 --query "Instances[0].InstanceId" --output text)

# ====== OBTENDO O IP PÚBLICO DA INSTÂNCIA EC2 ======
ipInstancia=$(aws ec2 describe-instances \
  --region $regiao \
  --instance-ids $idInstancia \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "A instância EC2 está disponível no IP: $ipInstancia"

# ====== TRANSFERIR O ARQUIVO compose.yaml PARA A INSTÂNCIA EC2 ======
echo "Transferindo o arquivo compose.yaml para a instância EC2..."
scp -i "$nomeChavePem.pem" compose.yaml ubuntu@$ipInstancia:/home/ubuntu/compose.yaml

# ====== RODAR O DOCKER COMPOSE NA INSTÂNCIA EC2 ======
echo "Rodando o compose na instância EC2..."
ssh -i "$nomeChavePem.pem" ubuntu@$ipInstancia << EOF
  cd /home/ubuntu
  sudo compose -f compose.yaml up -d
EOF

# ====== LISTANDO ======
echo "Instância criada com ID: $idInstancia"
echo "============================================="
echo "Buckets criados:"
echo " - $bucketRaw"
echo " - $bucketTrusted"
echo " - $bucketClient"
echo "Instância EC2: $idInstancia"
echo "Chave PEM: $nomeChavePem.pem"
