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

# ====== SCRIPT DE INICIALIZAÇÃO EC2 PRO BANCO DE DADOS======
read -r -d '' scriptEC2 <<'EOF_USERDATA'
#!/bin/bash
set -e
sudo apt update -y
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

mkdir -p /home/ubuntu/navix-banco
cd /home/ubuntu/navix-banco

# ===== Script SQL =====
cat <<'EOF_SQL' > navix.sql
-- DDL (Data Definition Language)
DROP DATABASE IF EXISTS navix;
CREATE DATABASE IF NOT EXISTS navix;
USE navix;

CREATE TABLE cargo(
    id INT PRIMARY KEY AUTO_INCREMENT,
    titulo VARCHAR(30)
);

CREATE TABLE empresa(
    id INT PRIMARY KEY AUTO_INCREMENT,
    razaoSocial VARCHAR(50),
    cnpj VARCHAR(14),
    codigo_ativacao VARCHAR(20)
);

CREATE TABLE endereco(
    id INT PRIMARY KEY AUTO_INCREMENT,
    rua VARCHAR(50),
    numero INT,
    cep CHAR(8),
    bairro VARCHAR(30),
    cidade VARCHAR(30),
    estado VARCHAR(20),
    pais VARCHAR(20),
    fkEmpresa INT NOT NULL,
    CONSTRAINT fkEnderecoEmpresa FOREIGN KEY(fkEmpresa) REFERENCES empresa(id)
);

CREATE TABLE funcionario(
    id INT PRIMARY KEY AUTO_INCREMENT,
    fkEmpresa INT NOT NULL,
    nome VARCHAR(50),
    sobrenome VARCHAR(50),
    telefone VARCHAR(11),
    email VARCHAR(100) UNIQUE,
    senha VARCHAR(250),
    statusPerfil ENUM("Inativo", "Ativo") NOT NULL DEFAULT("Ativo"),
    fkCargo INT NOT NULL,
    caminhoImagem VARCHAR(500) DEFAULT("../assets/img/foto-usuario.png"),
    CONSTRAINT fkEmpresaFuncionario FOREIGN KEY(fkEmpresa) REFERENCES empresa(id),
    CONSTRAINT fkCargoFuncionario FOREIGN KEY(fkCargo) REFERENCES cargo(id)
);

CREATE TABLE lote(
    id INT PRIMARY KEY AUTO_INCREMENT,
    codigo_lote VARCHAR(50) UNIQUE,
    data_fabricacao DATE,
    fkEmpresa INT,
    status ENUM('Ativo','Manutenção','Inativo'),
    CONSTRAINT fkEmpresaLote FOREIGN KEY(fkEmpresa) REFERENCES empresa(id),
    UNIQUE KEY uk_lote_empresa (codigo_lote, fkEmpresa)
);

CREATE TABLE modelo(
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(50),
    status ENUM('Ativo','Descontinuado'),
    versaoPilotoAutomatico VARCHAR(45),
    fkEmpresa int,
    CONSTRAINT fkEmpresaModelo FOREIGN KEY(fkEmpresa) REFERENCES empresa(id),
    UNIQUE KEY uk_modelo_empresa (nome, versaoPilotoAutomatico, fkEmpresa)
);

CREATE TABLE veiculo(
    id INT PRIMARY KEY AUTO_INCREMENT,
    fkModelo INT NOT NULL,
    fkLote INT NOT NULL,
    data_ativacao DATE,
    quantidade_modelo INT,
    CONSTRAINT fkModeloVeiculo FOREIGN KEY(fkModelo) REFERENCES modelo(id),
    CONSTRAINT fkLoteVeiculo FOREIGN KEY(fkLote) REFERENCES lote(id)
);

CREATE TABLE hardware(
    id INT PRIMARY KEY AUTO_INCREMENT,
    tipo ENUM('CPU','RAM','DISCO')
);

CREATE TABLE parametroHardware(
    fkHardware INT,
    fkModelo INT,
    unidadeMedida VARCHAR(15),
    parametroMinimo INT,
    parametroNeutro INT,
    parametroAtencao INT,
    parametroCritico INT,
    CONSTRAINT fkHardwareParametro FOREIGN KEY(fkHardware) REFERENCES hardware(id),
    CONSTRAINT fkModeloParametro FOREIGN KEY(fkModelo) REFERENCES modelo(id),
    PRIMARY KEY(fkHardware, fkModelo, unidadeMedida)
);

INSERT INTO cargo (titulo) VALUES
('Administrador'),
('Engenheiro automotivo'),
('Engenheiro de qualidade');

INSERT INTO empresa (razaoSocial, cnpj, codigo_ativacao) VALUES
('Tech Solutions LTDA', '12345678000195', 'ABC123'),
('Auto Veículos S.A.', '98765432000189', 'XYZ987');

INSERT INTO endereco (rua, numero, cep, bairro, cidade, estado, pais, fkEmpresa) VALUES 
('Rua das Flores', 123, '12345678', 'Centro', 'São Paulo', 'SP', 'Brasil', 1),
('Av. Paulista', 1000, '87654321', 'Bela Vista', 'São Paulo', 'SP', 'Brasil', 2);

INSERT INTO funcionario (fkEmpresa, nome, sobrenome, telefone, statusPerfil, email, senha, fkCargo) VALUES 
(1, 'Carlos', 'Silva', '11987654321', 'Ativo', 'carlos.silva@tech.com', 'senha123', 1),
(2, 'Ana', 'Oliveira', '11987654322', 'Ativo', 'ana.oliveira@auto.com', 'senha456', 2),
(1, 'Gabriel', 'Santos', '11982654321', 'Ativo', 'gabriel.santos@tech.com', 'senha143', 3);

INSERT INTO hardware (tipo) VALUES ('CPU'), ('RAM'), ('DISCO');
EOF_SQL

# ===== Dockerfile =====
cat <<'EOF_DOCKER' > Dockerfile
FROM mysql:8.0
LABEL maintainer="Guilherme Vitor"
COPY navix.sql /docker-entrypoint-initdb.d/
EXPOSE 3306
EOF_DOCKER

# ===== Build e Run =====
sudo docker build -t navix-mysql .
sudo docker run -d \
  --name mysql-navix \
  -e MYSQL_ROOT_PASSWORD=sptech \
  -p 3306:3306 \
  navix-mysql

echo "Container MySQL iniciado com sucesso!"
EOF_USERDATA

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

echo "Instância criada com ID: $idInstancia"
echo "============================================="
echo "Buckets criados:"
echo " - $bucketRaw"
echo " - $bucketTrusted"
echo " - $bucketClient"
echo "Instância EC2: $idInstancia"
echo "Chave PEM: $nomeChavePem.pem"
