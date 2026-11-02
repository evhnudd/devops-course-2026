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

Имя узла: `devops-vm`, FQDN `devops-vm.devops.local` (строка `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts`). На хосте в `C:\Windows\System32\drivers\etc\hosts`: `192.168.56.101 devops.local`.
