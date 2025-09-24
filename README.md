# routertopc
Настройка туннелирования домашней сети через ПК с Windows и Linux.

## Описание
Данный репозиторий содержит инструкции по настройке туннелирования домашней сети через компьютер, работающий под управлением Windows или Linux.

## Файлы в репозитории

- `README.md` - Основная документация и инструкции
- `setup-linux-tunnel.sh` - Автоматический скрипт настройки для Linux
- `linux-tunnel-config.example` - Пример конфигурационного файла

## Настройка для Linux

### Быстрая установка

Для автоматической настройки используйте прилагаемый скрипт:

```bash
# Клонируйте репозиторий
git clone https://github.com/ArkBee/routertopc.git
cd routertopc

# Запустите скрипт автоматической настройки
chmod +x setup-linux-tunnel.sh
./setup-linux-tunnel.sh

# Проверьте статус
./setup-linux-tunnel.sh --status
```

### Ручная настройка

#### Предварительные требования
- ОС Linux (Ubuntu, Debian, CentOS, Fedora и др.)
- Права root или sudo доступ
- Базовые знания работы с терминалом

### Установка необходимых пакетов

#### Ubuntu/Debian:
```bash
sudo apt update
sudo apt install iptables-persistent bridge-utils net-tools openssh-server
```

#### CentOS/RHEL/Fedora:
```bash
# CentOS/RHEL
sudo yum install iptables-services bridge-utils net-tools openssh-server

# Fedora
sudo dnf install iptables-services bridge-utils net-tools openssh-server
```

### Настройка IP Forwarding

1. Включите IP forwarding:
```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

2. Проверьте активацию:
```bash
cat /proc/sys/net/ipv4/ip_forward
# Должно вернуть 1
```

### Настройка iptables для туннелирования

1. Создайте правила NAT для пересылки трафика:
```bash
# Замените eth0 на ваш сетевой интерфейс
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
```

2. Сохраните правила:
```bash
# Ubuntu/Debian
sudo netfilter-persistent save

# CentOS/RHEL
sudo service iptables save
```

### Настройка SSH туннеля

1. Настройка SSH сервера:
```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

2. Создание SSH туннеля (на клиентской машине):
```bash
# Локальный порт forwarding
ssh -L LOCAL_PORT:DESTINATION_HOST:DESTINATION_PORT username@tunnel_server

# Динамический SOCKS прокси
ssh -D 8080 username@tunnel_server

# Удаленный порт forwarding
ssh -R REMOTE_PORT:localhost:LOCAL_PORT username@tunnel_server
```

### Настройка OpenVPN (альтернативный метод)

1. Установка OpenVPN:
```bash
# Ubuntu/Debian
sudo apt install openvpn easy-rsa

# CentOS/RHEL/Fedora
sudo yum install openvpn easy-rsa  # CentOS/RHEL
sudo dnf install openvpn easy-rsa  # Fedora
```

2. Настройка сервера:
```bash
sudo make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
sudo ./easyrsa init-pki
sudo ./easyrsa build-ca
sudo ./easyrsa gen-req server nopass
sudo ./easyrsa sign-req server server
sudo ./easyrsa gen-dh
```

### Настройка сетевого моста

1. Создание моста:
```bash
sudo brctl addbr br0
sudo brctl addif br0 eth0
sudo ip addr add 192.168.1.100/24 dev br0
sudo ip link set dev br0 up
```

2. Настройка через netplan (Ubuntu 18.04+):
```yaml
# /etc/netplan/01-network-manager-all.yaml
network:
  version: 2
  renderer: networkd
  bridges:
    br0:
      interfaces: [eth0]
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

### Мониторинг и диагностика

1. Проверка сетевых соединений:
```bash
# Просмотр активных соединений
ss -tulpn

# Проверка таблицы маршрутизации
ip route show

# Мониторинг трафика
sudo tcpdump -i any
```

2. Проверка работы туннеля:
```bash
# Проверка связности
ping 8.8.8.8

# Трассировка маршрута
traceroute google.com

# Проверка портов
nmap -p 22,80,443 localhost
```

### Автоматизация запуска

1. Создайте systemd сервис:
```bash
sudo nano /etc/systemd/system/router-tunnel.service
```

2. Содержимое файла сервиса:
```ini
[Unit]
Description=Router Tunnel Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-tunnel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

3. Создайте скрипт настройки:
```bash
sudo nano /usr/local/bin/setup-tunnel.sh
sudo chmod +x /usr/local/bin/setup-tunnel.sh
```

4. Пример содержимого скрипта:
```bash
#!/bin/bash
# Включение IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Настройка iptables
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT

echo "Tunnel setup completed"
```

5. Активация сервиса:
```bash
sudo systemctl enable router-tunnel.service
sudo systemctl start router-tunnel.service
```

### Устранение неполадок

1. Проверка логов:
```bash
# Системные логи
sudo journalctl -u router-tunnel.service

# Сетевые логи
sudo tail -f /var/log/syslog | grep -i network
```

2. Отладка iptables:
```bash
# Просмотр правил
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

# Очистка правил (осторожно!)
sudo iptables -F
sudo iptables -t nat -F
```

### Безопасность

1. Настройка firewall:
```bash
# Установка ufw (Ubuntu)
sudo apt install ufw
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow from 192.168.1.0/24
```

2. Настройка fail2ban:
```bash
sudo apt install fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Конфигурационный файл

Для удобства настройки используйте прилагаемый пример конфигурации:

```bash
# Скопируйте пример конфигурации
cp linux-tunnel-config.example linux-tunnel-config.conf

# Отредактируйте под ваши нужды
nano linux-tunnel-config.conf

# Примените конфигурацию
source linux-tunnel-config.conf
```

### Поддержка

Если у вас возникли вопросы или проблемы с настройкой, создайте issue в данном репозитории с подробным описанием проблемы и конфигурации вашей системы.
