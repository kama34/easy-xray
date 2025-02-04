Создать пользователя 
```
useradd -m username
```

Поставить пароль
```
passwd username
```

Здесь мы даём новому пользователю возможность выполнять команды от root через sudo
```
visudo
```

Открывает конфигурацию sudo для редактирования.

Проверяем, что есть строки:

```
%wheel ALL=(ALL) ALL
```

или

```
%sudo ALL=(ALL) ALL
```

Добавляем пользователя в группу
```
usermod -aG sudo username
```

Настраиваем firewall
Проверяем статус
```
sudo ufw status
```

Если выключен, то включаем
```
sudo ufw enable
```

Разрешаем HTTP (80) и HTTPS (443):
```
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Открываем доступ по SSH (если не открыли ранее, иначе потеряем доступ!):
```
sudo ufw allow OpenSSH
```

Перезапускаем ufw, чтобы применить правила:
```
sudo ufw reload
```

Проверяем, что правила добавлены:
```
sudo ufw status verbose
```

Скачиваем необходимые компаненты
```
sudo apt update && sudo apt upgrade -y
sudo apt install -y jq openssl
jq --version
openssl version
```

Войти в пользователя
```
sudo -i -u username
```
```
cd username
```

Далее разворачиваем этот проект у себя на сервере и заходим в его папку
```
git clone https://github.com/kama34/easy-xray.git
cd easy-xray
```

Запускаем установку
```
chmod +x ex.sh
./ex.sh help
sudo ./ex.sh install
```

Make CDN support? (y/N) - N
Generate configs? (Y/n) - Y
Enter domain name to use with IPv6 and CDN (e.g. Cloudflare),
or leave blank for simple default configuration: - пропускаем нажимая Enter

Enter IPv4 or IPv6 address of your xray server, or its domain name: - вводим ip сервера

Generate xray private and public keys? (Y/n) - Y

Better if it is quite popular and not blocked in your country:
(1) duckduckgo.com (default)
(2) www.microsoft.com
(3) www.google.com
(4) www.bing.com
(5) www.yahoo.com
(6) www.adobe.com
(7) aws.amazon.com
(8) www.aliexpress.com
(9) your variant

3

Add other users? (Y/n)
y

Enter usernames separated by spaces
Test

Copy config to xray's dir and restart xray? (Y/n)
y

Which config to use, server/client/other? (S/c/o)
s

./ex.sh link conf/config_client_Test.json

Если необходимо сделать так, чтобы русские сайты не блокировались, надо в conf/config_server.json в routing убрать секции с "block", где упоминаются customgeo и .ru, и выполните sudo ./ex.sh push.