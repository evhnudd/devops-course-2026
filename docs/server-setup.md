# Конфигурация виртуальной машины devops-vm

Автор: Севостьянова Е.К., ЭФБО-03-24. Хост: Windows 11, Oracle VirtualBox 7.2.20.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя ВМ | devops-vm (каталог `D:\VirtualBox VMs\devops-vm`) |
| Гостевая ОС | Ubuntu Server 24.04.5 LTS (Linux / Ubuntu 64-bit), установка «Use an entire disk» (LVM) |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ VDI, динамически расширяемый |
| Паравиртуализация | `none` (на хосте активен Hyper-V, с провайдером KVM ядро зависало при загрузке на тесте raid6) |

Команды создания (хост, PowerShell):

```powershell
$vb = 'C:\Program Files (x86)\VBoxManage.exe'
& $vb createvm --name devops-vm --ostype Ubuntu_64 --basefolder 'D:\VirtualBox VMs' --register
& $vb modifyvm devops-vm --memory 2048 --cpus 2 --nic1 nat --nic2 hostonly `
    --hostonlyadapter2 'VirtualBox Host-Only Ethernet Adapter' --paravirt-provider none
& $vb createmedium disk --filename 'D:\VirtualBox VMs\devops-vm\devops-vm.vdi' --size 25600
```

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера VirtualBox | Адрес | Назначение |
|---|---|---|---|
| enp0s3 | NAT (адаптер 1) | 10.0.2.15/24 (DHCP) | Выход в Интернет, доступ к репозиториям пакетов |
| enp0s8 | Host-only, «VirtualBox Host-Only Ethernet Adapter» (адаптер 2) | 192.168.56.101/24 (DHCP VirtualBox) | Доступ с хоста напрямую: веб-сервер, SSH по имени devops.local |

## 3. Правило проброса портов

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| ssh | TCP | 127.0.0.1 | 2222 | — | 2222 (до усиления защиты — 22) |

```powershell
& $vb modifyvm devops-vm --natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
```

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| student (uid 1000) | student, adm, cdrom, sudo, dip, plugdev, lxd | создан при установке; вход по SSH запрещён (`AllowUsers devops`), только локальная консоль, пароль |
| devops (uid 1001) | devops, sudo, users (+ docker с ПР № 7) | SSH только по ключу ed25519 `~/.ssh/devops_vm` (комментарий `devops-vm-key`); пароль нужен только для sudo |

Восстановление:

```bash
sudo adduser devops && sudo usermod -aG sudo devops
# на хосте: ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
# type $env:USERPROFILE\.ssh\devops_vm.pub | ssh devops@127.0.0.1 -p 2222 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Файл `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Основной `/etc/ssh/sshd_config` не изменяется (копия — `/etc/ssh/sshd_config.backup`). Дополняющий файл `/etc/ssh/sshd_config.d/99-hardening.conf` (root:root, 644):

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована (файл читается раньше 99-, первое значение побеждает).

Активация по сокету отключена, иначе порт берётся из `ssh.socket`:

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd      # 0.0.0.0:2222
```

После этого — изменить проброс порта (раздел 3) на гостевой порт 2222.

## 6. Правила межсетевого экрана

Политики: `deny incoming`, `allow outgoing`, routed — disabled. Журналирование: `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp | LIMIT IN | SSH rate-limited |
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'   # ДО включения!
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
```

## 7. Снимки состояния

| Снимок | Момент создания |
|---|---|
| 01-clean-install | 02.11.2026, после установки ОС и `apt upgrade` |
| 02-keys-configured | 02.11.2026, после создания devops и настройки ключей |
| 03-ssh-hardened | 02.11.2026, после усиления SSH |
| 04-nginx-https | 02.11.2026, после настройки Nginx и HTTPS для devops.local |
| 05-docker-compose | 03.11.2026, после установки Docker и запуска проекта app (Flask + PostgreSQL) |

Имя узла: `devops-vm`, FQDN `devops-vm.devops.local` (строка `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts`). На хосте в `C:\Windows\System32\drivers\etc\hosts`: `192.168.56.101 devops.local`.

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` из репозитория Ubuntu (`sudo apt install -y nginx`), версия 1.24.0; master — root, worker — www-data |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка в `/etc/nginx/sites-enabled/`; ссылка `sites-enabled/default` удалена (файл в `sites-available` сохранён) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталог 755, файлы 644 (`index.html`, `404.html`) |
| Сертификат | `/etc/ssl/certs/devops.crt`, root:root, 644 |
| Закрытый ключ | `/etc/ssl/private/devops.key`, root:root, 600 |
| Срок действия сертификата | 365 дней (выпущен 02.11.2026, истекает 02.11.2027) |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Доставка содержимого | `scripts/deploy.sh` (rsync `--delete --chmod=D755,F644` из каталога `site/` репозитория) |

Формирование сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Восстановление:

```bash
sudo apt update && sudo apt install -y nginx rsync
sudo mkdir -p /var/www/devops-site && sudo chown -R devops:devops /var/www/devops-site
# создать сертификат (команда выше) и файл конфигурации (выше)
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
# на хосте: scp devops:/etc/ssl/certs/devops.crt ~/devops.crt && scripts/deploy.sh
```

## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Docker Engine | из официального репозитория `download.docker.com` (пакеты `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`), версия 29.9.2, Compose v5.7.0 |
| Группа docker | `devops` (имеет и право sudo; учётным записям без sudo группа не выдаётся) |
| Проект на сервере | `~/app` (`/home/devops/app`), доставляется с хоста `rsync -avz --delete --exclude=.env app/ devops:app/` |
| Файл секретов | `~/app/.env`, владелец devops, права 600, создаётся только на сервере из `.env.example`, пароль `openssl rand -hex 16`; в репозитории — только `.env.example`, `.env` в `.gitignore` и `.dockerignore` |
| Сервисы | `db` — `postgres:16-alpine`, healthcheck `pg_isready`; `app` — образ `devops-app:1.0` (python:3.12-slim, пользователь app), `depends_on: condition: service_healthy`; оба `restart: unless-stopped` |
| Публикация портов | `127.0.0.1:5000:5000` (только loopback); порт 5432 не публикуется, СУБД доступна только в сети `app_backend` по имени `db` |
| Именованный том | `app_db_data` → `/var/lib/postgresql/data` (сохраняется при `docker compose down`, удаляется при `down -v`) |
| Обратный прокси | в блоке 443 `/etc/nginx/sites-available/devops-site` добавлено `location /app/` → `proxy_pass http://127.0.0.1:5000/` с заголовками Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto |

Установка Docker Engine:

```bash
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops     # затем новая SSH-сессия
```

Запуск проекта:

```bash
cd ~/app && cp .env.example .env && chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
```

Фрагмент Nginx:

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Особенность стенда: на хосте активен Hyper-V, VirtualBox работает через NEM. Ядро периодически зависало в initramfs на этапе «Loading essential drivers» (бенчмарк raid6). Добавлено в `/etc/default/grub`:
`GRUB_CMDLINE_LINUX_DEFAULT="... modprobe.blacklist=raid6_pq,raid456,async_raid6_recov,btrfs"` и выполнен `sudo update-grub` (на LVM+ext4 эти модули не нужны).
