# Лабораторная работа №3. Облачные сети. Amazon VPC

- **Студент:** Splavski Maxim
- **Группа:** I2402
- **Специальность:** Informatică
- **Номер в группе:** `k = 16`, `X = 16 % 30 = 16`
- **Уровень:** продвинутый (Часть 1 + Часть 2, задания 1-14)
- **Репозиторий:** https://github.com/USM-Labs/timecapsule
- **Вариант NAT Gateway:** B - скрипты [`scripts/nat-up.sh`](../../scripts/nat-up.sh) и [`scripts/nat-down.sh`](../../scripts/nat-down.sh)
- **ADR:** [docs/adr/0002-database-placement.md](../adr/0002-database-placement.md)
- **Отчёт ЛР2:** [README.md](../../README.md) в корне репозитория

Все ресурсы в `eu-central-1`, имена по шаблону `timecapsule-dev-<роль>[-<зона>]`, теги `Name`, `Project=timecapsule`, `Environment=dev`, `Owner=maxsplavski`, `Lab=lab3`.

| Ресурс                  | Имя                                                       | ID / адрес                                                 |
| ----------------------- | --------------------------------------------------------- | ---------------------------------------------------------- |
| VPC                     | `timecapsule-dev-vpc`                                     | `vpc-0ee166a8bf2a798b6`, `10.16.0.0/16`                    |
| Internet Gateway        | `timecapsule-dev-igw`                                     | `igw-086e9965705621a10`                                    |
| Таблицы маршрутов       | `timecapsule-dev-public-rt`, `timecapsule-dev-private-rt` | `rtb-0b7467089fea51085`, `rtb-03c425148cd18f92a`           |
| bastion                 | `timecapsule-dev-bastion` (`public-b`)                    | `i-0dbb1d1f516212355`, `10.16.1.107`                       |
| web-server (Часть 1)    | `timecapsule-dev-web` (`public-a`)                        | `i-019a3d0b7cc047223`, `10.16.0.57` - завершён в задании 8 |
| db-server               | `timecapsule-dev-db` (`private-a`)                        | `i-06a75ca8d7700306d`, `10.16.10.184`                      |
| app-server              | `timecapsule-dev-app` (`public-a`)                        | `i-0667e5297625982ed`, `10.16.0.200`                       |
| Elastic IP              | `timecapsule-dev-app-eip`                                 | `63.189.89.102`                                            |
| Приватная зона Route 53 | `timecapsule.internal`                                    | `Z1045925MTM9QDX2LNB6`, `db` → `10.16.10.184`              |

> **Как сделаны скриншоты.** Ресурсы созданы AWS CLI с тегами
> (задания 2-5 - скрипт [`build-part1.sh`](build-part1.sh), остальные команды приведены в отчёте по ходу),
> а их состояние снято **в консоли AWS** (Chrome): таблицы маршрутов, Security Group, NAT Gateway, Network ACL,
> AMI, Elastic IP, Route 53, Tag Editor, CloudShell со скриптами `nat-up.sh`/`nat-down.sh`. Команды на серверах
> выполнялись с моего компьютера через bastion (`ssh web`, `ssh db`, `ssh app`) - это реальный вывод,
> отрисованный в нейтральное окно терминала. На скриншотах страниц сверху добавлена строка адреса.
> Мой домашний IP замаскирован (`89.149.93.x`).

---

## Часть 1. Базовый уровень

### Задание 1. План адресов

| Подсеть     | Зона доступности | Диапазон        | Первый и последний адрес, доступный экземплярам | Сколько адресов доступно экземплярам |
| ----------- | ---------------- | --------------- | ----------------------------------------------- | ------------------------------------ |
| `public-a`  | `eu-central-1a`  | `10.16.0.0/24`  | `10.16.0.4` - `10.16.0.254`                     | 251                                  |
| `public-b`  | `eu-central-1b`  | `10.16.1.0/24`  | `10.16.1.4` - `10.16.1.254`                     | 251                                  |
| `private-a` | `eu-central-1a`  | `10.16.10.0/24` | `10.16.10.4` - `10.16.10.254`                   | 251                                  |
| `private-b` | `eu-central-1b`  | `10.16.11.0/24` | `10.16.11.4` - `10.16.11.254`                   | 251                                  |

> **Почему доступных адресов не 256? Какие адреса подсети `10.16.0.0/24` занимает AWS и для чего? Сколько ещё подсетей `/24` поместится в VPC?**
> AWS резервирует в каждой подсети 5 адресов: `10.16.0.0` - адрес сети, `.1` - маршрутизатор VPC, `.2` - DNS-сервер VPC (база VPC + 2), `.3` - зарезервирован на будущее, `.255` - широковещательный (в VPC broadcast не поддерживается, но адрес занят). Остаётся 256 - 5 = 251. В `/16` помещается 2^(24-16) = 256 подсетей `/24`; четыре заняты, поэтому поместится ещё **252**.

### Задание 2. VPC и подсети

Создана `timecapsule-dev-vpc` (`10.16.0.0/16`, без IPv6), включены `DNS resolution` и `DNS hostnames`, созданы четыре подсети из таблицы.

> **Является ли подсеть `public-a` сейчас публичной? Почему?**
> Нет. Подсеть становится публичной не из-за названия, а из-за маршрута `0.0.0.0/0` в Internet Gateway в её таблице маршрутов. Сразу после создания она связана с основной таблицей VPC, где есть только маршрут `local`, и Internet Gateway ещё не существует, поэтому выхода в интернет у неё нет.

### Задание 3. Internet Gateway и таблицы маршрутов

![public-rt routes](screenshots/03-public-rt-routes.jpg)
_`timecapsule-dev-public-rt`: `0.0.0.0/0 → igw-086e9965705621a10` и `10.16.0.0/16 → local`, связана с 2 подсетями._

![public-rt subnets](screenshots/03-public-rt-subnets.jpg)
_Явные связи `public-rt`: `public-a` (`10.16.0.0/24`) и `public-b` (`10.16.1.0/24`)._

![private-rt routes](screenshots/03-private-rt-routes.jpg)
_`timecapsule-dev-private-rt`: только маршрут `local`._

![private-rt subnets](screenshots/03-private-rt-subnets.jpg)
_Явные связи `private-rt`: `private-a` (`10.16.10.0/24`) и `private-b` (`10.16.11.0/24`)._

Для `public-a` и `public-b` включён `Enable auto-assign public IPv4 address`.

> **Какой маршрут есть в обеих таблицах, хотя вы его не добавляли? Что он даёт? Куда уйдёт пакет из `private-a`, адресованный `8.8.8.8`?**
> Маршрут `10.16.0.0/16 → local`. Его AWS добавляет в каждую таблицу VPC, удалить его нельзя: он обеспечивает связь между всеми подсетями VPC, в том числе из разных зон доступности. Для `8.8.8.8` в `private-rt` нет подходящего маршрута (только `local`), поэтому пакет никуда не уйдёт: маршрутизатор VPC его отбросит.

### Задание 4. Security Group

![bastion-sg](screenshots/04-bastion-sg.jpg)
_`timecapsule-dev-bastion-sg`: SSH (22) только с моего IP `/32`._

![web-sg](screenshots/04-web-sg.jpg)
_`timecapsule-dev-web-sg`: HTTP (80) с `0.0.0.0/0`, SSH (22) только от `bastion-sg`._

![db-sg](screenshots/04-db-sg.jpg)
_`timecapsule-dev-db-sg`: PostgreSQL (5432) только от `web-sg`, SSH (22) только от `bastion-sg`._

> **Почему в `db-sg` источником указана группа `web-sg`, а не адрес веб-сервера или диапазон `10.16.0.0/16`?**
> Ссылка на группу разрешает доступ всем экземплярам, у которых есть `web-sg`, независимо от их адресов. Если веб-сервер пересоздать (как в задании 8, где `web-server` заменил `app-server` с другим IP) или добавить второй, правило менять не нужно. Диапазон `10.16.0.0/16` был бы слишком широким: к базе смог бы подключиться любой сервер VPC, в том числе bastion.

### Задание 5. Экземпляры

![web-server](screenshots/05-web-server.jpg)
_Страница `web-server` по публичному IP: имя `ip-10-16-0-57` и приватный адрес `10.16.0.57` из `10.16.0.0/24` (страница создана скриптом User data)._

![ssh](screenshots/05-ssh-jump.png)
_`~/.ssh/config` с `ProxyJump bastion` и подключения `ssh bastion`, `ssh web`, `ssh db`._

![dnf hang](screenshots/05-db-dnf-hang.png)
_`sudo dnf -y install postgresql16-server` на `db-server` за 60 секунд не выводит ни строки и прерывается (`timeout`, код 124)._

> **Почему `db-server` не может скачать пакеты, хотя `web-server` это делает? Что нужно добавить в сеть, чтобы это стало возможно, и при этом `db-server` остался недоступным из интернета?**
> У `db-server` нет публичного адреса, а в `private-rt` нет маршрута `0.0.0.0/0`, поэтому пакеты к репозиториям никуда не уходят. У `web-server` есть публичный IP и маршрут в Internet Gateway. Нужен NAT Gateway в публичной подсети и маршрут `0.0.0.0/0 → NAT` в `private-rt`: NAT выпускает исходящие соединения, подменяя адрес на свой, но не принимает новых соединений снаружи.

### Задание 6. Временный NAT Gateway

![nat available](screenshots/06-nat-available.jpg)
_`timecapsule-dev-nat-a` в `public-a`, `Available`, публичный адрес `18.197.248.135` (Elastic IP `timecapsule-dev-nat-a-eip`)._

![checkip](screenshots/06-checkip.png)
_`curl https://checkip.amazonaws.com` на `db-server` вернул `18.197.248.135` - это Elastic IP NAT Gateway._

![dnf](screenshots/06-dnf-install.png)
_Через NAT Gateway `dnf update` и установка `postgresql16-server` проходят._

![pg setup](screenshots/06-pg-setup.png)
_`listen_addresses = '*'`, строка `host all all 10.16.0.0/24 scram-sha-256` в `pg_hba.conf`, PostgreSQL слушает `0.0.0.0:5432`, база `lab3` с владельцем `student`._

![blackhole](screenshots/06-blackhole.jpg)
_После удаления шлюза маршрут `0.0.0.0/0` в `private-rt` в состоянии `Blackhole`. Затем маршрут удалён, Elastic IP освобождён._

![nat deleted](screenshots/06-nat-deleted.jpg)
_В `NAT gateways` шлюз `timecapsule-dev-nat-a` в состоянии `Deleted`._

> **Какой адрес вернула первая команда? Почему это не адрес `db-server`?**
> `18.197.248.135` - Elastic IP NAT Gateway. У `db-server` только приватный адрес `10.16.10.184`, который в интернете не маршрутизируется. NAT Gateway заменяет адрес отправителя на свой публичный, поэтому внешний сервис видит адрес шлюза, а ответы возвращаются через NAT обратно к `db-server`.

> **Доступ к базе ограничивают три механизма: отсутствие публичного адреса и маршрута в Internet Gateway, Security Group `db-sg` и `pg_hba.conf`. Что делает каждый из них? Что произойдёт, если ошибиться только в одном?**
> Маршрутизация и отсутствие публичного IP делают сервер недостижимым из интернета на сетевом уровне. Security Group на уровне сетевого интерфейса пропускает к порту 5432 только экземпляры с `web-sg`. `pg_hba.conf` на уровне самого PostgreSQL решает, с каких адресов, к какой базе и каким способом можно войти, и требует пароль. Если ошибиться в одном механизме (например, открыть 5432 для `0.0.0.0/0`), два других продолжат защищать базу: это эшелонированная защита (defense in depth). Опасно, только когда ошибок несколько одновременно.

> **Почему PostgreSQL продолжает работать после удаления NAT Gateway? Что придётся сделать, когда на `db-server` понадобятся обновления безопасности?**
> NAT нужен только для исходящих соединений в интернет. Подключения от веб-сервера к базе идут внутри VPC по маршруту `local`, которому NAT не нужен. Для обновлений придётся снова поднять NAT Gateway и маршрут, установить обновления и удалить шлюз; в Части 2 это делают скрипты `nat-up.sh` и `nat-down.sh`.

### Задание 7. Проверки

![psql](screenshots/07-psql-web.png)
_С `web-server`: `psql -h 10.16.10.184 -U student -d lab3 -c "SELECT version();"` → PostgreSQL 16.15._

![port check](screenshots/07-port-check.png)
_Порт 5432: с `web-server` - `open`, с `bastion` - `closed`._

> **Почему с `web-server` порт открыт, а с `bastion` нет, хотя оба сервера в одной VPC и маршрут между ними есть?**
> Маршрут только доставляет пакет, а решение принимает Security Group `db-sg`: порт 5432 разрешён только от экземпляров с группой `web-sg`. У bastion группа `bastion-sg`, ей разрешён только порт 22, поэтому SYN к 5432 молча отбрасывается и соединение истекает по таймауту.

![isolation](screenshots/07-db-isolation.png)
_`curl -m 5 https://github.com` с `db-server` - `Connection timed out`._

> **Почему запрос не проходит? Можно ли из интернета подключиться к порту 5432 `db-server`? Объясните по цепочке: маршрут, адрес, фильтры.**
> Маршрут: в `private-rt` нет `0.0.0.0/0` (NAT удалён), пакет к GitHub некуда отправить. Адрес: у `db-server` нет публичного IP, Internet Gateway нечем заменить приватный адрес, а снаружи до `10.16.10.184` не дойти, потому что приватные адреса в интернете не маршрутизируются. Фильтры: даже если бы путь был, `db-sg` пускает 5432 только от `web-sg`, а `pg_hba.conf` - только из `10.16.0.0/24`. Поэтому подключиться из интернета нельзя.

**Network ACL.** В Network ACL по умолчанию `acl-01c5141d88e787cd6` (связан со всеми 4 подсетями) добавлено входящее правило `90 DENY All traffic <мой IP>/32`.

![nacl rule](screenshots/07-nacl-rule90.jpg)
_Входящие правила ACL: `90 All traffic 89.149.93.x/32 Deny` перед `100 0.0.0.0/0 Allow`._

![nacl blocked](screenshots/07-nacl-blocked.png)
_С моего IP: `ssh bastion` - `Operation timed out`, сайт - таймаут (`000`)._

![nacl other network](screenshots/07-nacl-other-network.png)
_В это же время из AWS CloudShell (другой внешний адрес `63.179.189.191`) сайт `http://3.66.18.60` открывается._

![nacl restored](screenshots/07-nacl-restored.png)
_После удаления правила 90 SSH и сайт с моего компьютера снова работают._

> Проверку «с телефона через мобильный интернет» заменил проверкой из AWS CloudShell: у него свой внешний адрес, который правилом 90 не запрещён, так же как адрес оператора мобильной связи.

> **Почему заблокировано и SSH, и сайт, хотя вы не меняли ни одной Security Group? Почему с телефона сайт открывается? Почему правило должно иметь номер меньше 100?**
> Network ACL работает на границе подсети, до Security Group, и правило 90 запрещает весь трафик с моего адреса во все подсети, связанные с этим ACL, на любой порт. Поэтому блокируются и SSH на bastion, и HTTP на веб-сервер. Запрос с другого адреса (телефон, в моём случае CloudShell) правилу 90 не соответствует и пропускается правилом 100 `allow 0.0.0.0/0`. Правила ACL проверяются по возрастанию номера до первого совпадения, поэтому запрещающее правило должно стоять раньше разрешающего 100, иначе до него дело не дойдёт.

![tag editor](screenshots/07-tag-editor.jpg)
_Tag Editor (`eu-central-1`, `All supported resource types`, `Project = timecapsule`): 21 ресурс - VPC, 4 подсети, IGW, 3 таблицы маршрутов, Network ACL, 4 Security Group (bastion, web, db и группа по умолчанию), 3 экземпляра (bastion, app, db), их 3 диска и Elastic IP. Основной таблице маршрутов, ACL и SG по умолчанию теги добавлены вручную. Удалённые ресурсы (временный NAT Gateway, webserver, снимок AMI) в списке больше не видны._

> **Как по тегам найти все ресурсы, которые нужно удалить после окончания проекта? Зачем нужен тег `Owner`, если аккаунт личный?**
> В Tag Editor или через `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=timecapsule` можно получить список всех ресурсов проекта (а с `Environment=dev` или `Lab=lab3` - только нужной части) и удалить их по этому списку; по тем же тегам Cost Explorer показывает расходы проекта. `Owner` отвечает, кого спросить о ресурсе. В личном аккаунте это кажется лишним, но это привычка рабочего соглашения: аккаунт могут открыть преподаватель или коллеги, ресурсы потом переедут в общий аккаунт команды, а автоматизация (уведомления, очистка) использует `Owner`, чтобы найти ответственного.

---

## Часть 2. Продвинутый уровень

### Задание 8. Перенос сервера ЛР2 в новую сеть

`webserver` ЛР2 запущен, из него создан образ `timecapsule-dev-app-lab2` (`ami-0429a1a857dd53c39`, теги на образ и снимок), из образа запущен `timecapsule-dev-app` в `public-a` с `web-sg`. `web-server` из Части 1 завершён.

![ami](screenshots/08-ami.jpg)
_`EC2` → `AMIs`: образ `timecapsule-dev-app-lab2` в состоянии `Available`._

![app-server](screenshots/08-app-server.png)
_`ssh app` (через bastion): адрес `10.16.0.200`, работают nginx, PHP-FPM и локальный PostgreSQL, код ЛР2 (коммит `fd2bfe3`), `DB_HOST=localhost`, файл капсулы в `storage/uploads`._

> **Что содержит образ? Какие данные из ЛР2 оказались на `app-server` без всякой установки? Где сейчас хранится база данных приложения?**
> Образ - снимок корневого тома EBS `webserver` с описанием (архитектура, тип загрузки). На `app-server` сразу оказались ОС с установленными nginx, PHP 8.4, PostgreSQL 16, Composer и git; их настройки; код с `vendor/` и `.env`; `~/deploy.sh`; загруженные файлы в `storage/uploads` и сама локальная база ЛР2 в `/var/lib/pgsql`. Сразу после запуска база всё ещё хранилась локально на диске `app-server` (`localhost`), а не на `db-server`.

### Задание 9. Elastic IP

Elastic IP `timecapsule-dev-app-eip` = `63.189.89.102`, привязан к `timecapsule-dev-app`; в `.env` `APP_URL=http://63.189.89.102`.

![eip](screenshots/09-eip.jpg)
_`Elastic IPs`: `timecapsule-dev-app-eip` `63.189.89.102` привязан к `i-0667e5297625982ed` (`10.16.0.200`)._

![app eip](screenshots/09-app-eip.jpg)
_Приложение по Elastic IP `http://63.189.89.102`._

> Замечание: `sed -i` пересоздаёт `.env`, и группа `apache` сбрасывается на `ec2-user`. PHP-FPM перестаёт читать `.env`, и `/health` отвечает `db: error` (`password authentication failed` - берётся пароль по умолчанию). Исправил командой `sudo chgrp apache .env`; дальше после каждой правки `.env` возвращал группу.

> **Почему Elastic IP нужен `app-server`, но не нужен bastion? Сколько стоит Elastic IP, пока сервер остановлен, и почему? Понадобится ли Elastic IP, когда перед сервером появится балансировщик?**
> Адрес `app-server` знают пользователи и `APP_URL`, поэтому он должен быть постоянным. Адрес bastion нужен только администратору: после запуска достаточно поправить `HostName` в `~/.ssh/config`. Elastic IP стоит $0,005 в час (~$3,6 в месяц) всегда, в том числе у остановленного сервера: AWS берёт плату за каждый закреплённый публичный IPv4, потому что адрес зарезервирован за вами и недоступен другим. С балансировщиком нагрузки Elastic IP не понадобится: пользователи будут ходить на DNS-имя балансировщика, а `app-server` можно будет перенести в приватную подсеть.

### Задание 10. База данных приложения на `db-server`

![pg_hba](screenshots/10-pg-hba.png)
_Пользователь `timecapsule` с новым паролем и база `timecapsule`; строка `pg_hba.conf` ужесточена до `host timecapsule timecapsule 10.16.0.0/24 scram-sha-256`, PostgreSQL перезапущен._

> **Зачем для базы в отдельной сети нужен новый сильный пароль, если порт 5432 и так закрыт Security Group?**
> Security Group - лишь один слой: её могут изменить по ошибке, а к базе разрешено подключаться всему `web-sg`, то есть любому взломанному веб-серверу. Пароль ЛР2 лежал в `.env` и на старом диске (а значит, и в образе), так что его нужно считать скомпрометированным. Новый длинный случайный пароль с `scram-sha-256` - последний рубеж, если все сетевые фильтры пройдены.

### Задание 11. Приватная зона Route 53

![zone](screenshots/11-zone.jpg)
_Приватная зона `timecapsule.internal`, связанная с `timecapsule-dev-vpc`: запись `db.timecapsule.internal A 10.16.10.184 TTL 60`._

![dig app](screenshots/11-dig-app.png)
_С `app-server`: `dig +short db.timecapsule.internal` → `10.16.10.184`._

![dig mac](screenshots/11-dig-mac.png)
_С моего компьютера: пустой ответ, `NXDOMAIN`._

> **Почему с `app-server` имя находится, а с вашего компьютера нет? Что придётся изменить, если `db-server` пересоздадут с другим адресом?**
> Приватная зона отвечает только DNS-резолверу Route 53 внутри связанной VPC (адрес `10.16.0.2`), который используют серверы VPC. Мой компьютер спрашивает публичный DNS, где зоны `timecapsule.internal` нет. Если `db-server` пересоздадут, нужно изменить одну A-запись `db` в зоне; `.env` и код приложения менять не придётся (новый адрес подхватится в течение TTL 60 секунд).

### Задание 12. Перенос данных и переключение приложения

![dump](screenshots/12-dump-restore.png)
_`pg_dump` локальной базы ЛР2 и `psql -h db.timecapsule.internal ... -f timecapsule.sql`; в новой базе капсула `Lab 02 — привет из EC2`._

![switch](screenshots/12-switch.png)
_`DB_HOST=db.timecapsule.internal` и новый пароль в `.env` (группа `apache`), локальный PostgreSQL выключен (`inactive`), `/health` → `ok`._

![capsules](screenshots/12-capsules-list.jpg)
_Вход под пользователем ЛР2 по Elastic IP: капсула из ЛР2 на месте; в подвале `DB: db.timecapsule.internal`._

![capsule](screenshots/12-capsule-lr2.jpg)
_Капсула из ЛР2 открывается вместе с картинкой из `storage/uploads`._

Образ `timecapsule-dev-app-lab2` отменён (`Deregister`), снимок `snap-0545d89b8f6654c98` удалён.

> **Файлы, которые пользователи прикрепили к капсулам, переехали вместе с образом, а не вместе с базой. Где они лежат? Что с ними будет, если `app-server` удалить?**
> Они лежат на корневом томе EBS `app-server` в `/var/www/timecapsule/storage/uploads`, а в базе хранятся только ссылки на них. При `Terminate` корневой том по умолчанию удаляется, и файлы пропадут, хотя записи капсул в базе на `db-server` останутся с битыми ссылками. Поэтому файлы надо выносить в общее хранилище (S3) или хотя бы делать снапшоты тома.

### Задание 13. Деплой и обслуживание

**1. Новая версия.** Коммит `929b896 Show LR3 in footer`, деплой одной командой `ssh app ./deploy.sh`.

![deploy](screenshots/13-deploy-lr3.png)
_`git push` и `ssh app ./deploy.sh` через bastion: на сервере коммит `929b896`, база - `db.timecapsule.internal`._

![lr3](screenshots/13-lr3-footer.jpg)
_Строка «LR3: VPC, app + db in private subnet» в подвале по Elastic IP._

> **Почему в самом `deploy.sh` ничего менять не пришлось?**
> Скрипт работает на самом сервере и использует только локальные пути (`/var/www/timecapsule`), `git pull` по HTTPS через Internet Gateway и `.env`, где уже прописана новая база. Как добраться до сервера (через bastion), решает `~/.ssh/config` на моём компьютере, а не скрипт, поэтому команда `ssh app ./deploy.sh` выглядит так же, как в ЛР2.

**2. Отказ базы.**

![db down](screenshots/13-db-down.png)
_`db-server` остановлен: `/health` отвечает `{"db":"error"}` примерно через 5 секунд._

![health db down](screenshots/13-health-db-down.jpg)
_Ответ `/health` в браузере при остановленной базе._

![db up](screenshots/13-db-up.png)
_После запуска `db-server` приложение восстановилось само; приватный IP тот же `10.16.10.184`._

> **Что показал `/health` и почему? Изменился ли приватный адрес `db-server` после остановки и запуска?**
> `/health` вернул HTTP 500 и `"db":"error"`: он выполняет запрос к базе, а подключиться к `db.timecapsule.internal:5432` не удалось (сервер выключен, приложение ждёт таймаут подключения около 5 секунд). Приватный адрес не изменился: он закреплён за сетевым интерфейсом в подсети и сохраняется при Stop/Start, меняется только публичный. Поэтому A-запись и `.env` трогать не пришлось.

**3. Обновление пакетов на `db-server` (вариант B).** Скрипты запускались в AWS CloudShell из клона репозитория.

![nat-up](screenshots/13-nat-up.png)
_CloudShell, `./scripts/nat-up.sh`: Elastic IP, NAT Gateway в `public-a`, ожидание `available`, маршрут в `private-rt`; внешний адрес приватных подсетей `3.72.244.168`._

![dnf update](screenshots/13-db-dnf-update.png)
_На `db-server` внешний адрес = Elastic IP NAT (`3.72.244.168`); `sudo dnf -y update` проходит (`Nothing to do`: пакеты уже обновлены в задании 6)._

![nat-down](screenshots/13-nat-down.png)
_CloudShell, `./scripts/nat-down.sh`: маршрут удалён, NAT удалён и дождались `deleted`, Elastic IP освобождён с первой попытки._

Идентификаторы шлюза и адреса скрипты хранят в `scripts/nat-state.env`, файл добавлен в [`.gitignore`](../../.gitignore).

> **Почему `nat-down.sh` должен освобождать Elastic IP только после того, как NAT Gateway удалён?**
> Пока NAT Gateway существует, Elastic IP привязан к его сетевому интерфейсу, и `release-address` завершится ошибкой (адрес используется). Даже после перехода шлюза в `deleted` AWS отпускает адрес не мгновенно, поэтому скрипт ждёт `nat-gateway-deleted` и повторяет попытку с паузой. Если сначала потерять ID адреса или прервать скрипт, Elastic IP останется выделенным и будет оплачиваться.

### Задание 14. Архитектура и решение

![Архитектура](architecture.png)
_Схема: пользователи, мой компьютер и GitHub вне AWS; `timecapsule-dev-vpc` в `eu-central-1`, две AZ и четыре подсети, `timecapsule-dev-igw`, `bastion`/`app`/`db` с их Security Group, Elastic IP, приватная зона Route 53 и временный NAT Gateway (пунктир)._

ADR: [docs/adr/0002-database-placement.md](../adr/0002-database-placement.md) - сравнение базы на сервере приложения, в публичной и в приватной подсети (и RDS как следующий шаг); обновления через временный NAT и его стоимость; зачем Elastic IP и что изменит балансировщик.

---

## Итог

![NAT final](screenshots/99-nat-final.jpg)
_`NAT gateways`: оба временных шлюза (задание 6 и `nat-up.sh`) в состоянии `Deleted`, работающих нет._

![EIP final](screenshots/99-eip-final.jpg)
_`Elastic IPs`: остался только `timecapsule-dev-app-eip`._

`webserver` ЛР2 завершён, `bastion`, `app-server`, `db-server` остановлены; образов и снимков нет. VPC, подсети, таблицы маршрутов и Security Group оставлены для следующих работ.

## Контрольные вопросы

**1. Как проходит запрос пользователя от браузера до базы данных? Какие маршруты и правила фильтрации он проходит?**
Браузер обращается к Elastic IP `63.189.89.102:80`. Internet Gateway переводит его в приватный адрес `app-server` `10.16.0.200`; на входе в `public-a` пакет проверяет Network ACL (правило 100 allow), затем `web-sg` (80 от `0.0.0.0/0`). nginx передаёт запрос в PHP-FPM, приложение резолвит `db.timecapsule.internal` через DNS VPC в `10.16.10.184` и открывает соединение на 5432: оно идёт по маршруту `local`, через Network ACL `private-a` и `db-sg` (5432 от `web-sg`), а PostgreSQL проверяет `pg_hba.conf` (пользователь, база, подсеть `10.16.0.0/24`) и пароль. Ответы возвращаются тем же путём; Security Group stateful и ответ пропускают автоматически.

**2. Злоумышленник знает приватный IP `db-server`. Что ему нужно получить, чтобы подключиться к базе?**
Сам по себе приватный адрес из интернета бесполезен: до него нет маршрута. Нужно оказаться внутри VPC на машине с группой `web-sg` в подсети `10.16.0.0/24`, то есть взломать `app-server` (или получить доступ к AWS-аккаунту и поменять сеть). Кроме того, нужно знать логин и пароль пользователя `timecapsule` (они в `.env` на `app-server`). Поэтому самое ценное - сам `app-server`, его `.env` и SSH-ключ.

**3. Чем временный NAT Gateway лучше постоянного и какие неудобства он создаёт?**
Он дешевле (центы за сеанс обновления вместо ~$38 в месяц) и безопаснее: большую часть времени у `db-server` вообще нет пути в интернет, вредоносный код не сможет выгрузить данные или скачать что-то. Неудобства: обновления нужно запускать вручную (скриптами), во время работы шлюза нужно следить, чтобы его не забыли удалить, а пакеты нельзя поставить в любой момент, например при срочной уязвимости ночью; при каждом подъёме меняется внешний IP.

**4. Как изменится схема, если приложение должно пережить отказ зоны `eu-central-1a`? Каких ресурсов не хватает?**
Сейчас и `app-server`, и `db-server`, и NAT находятся в `eu-central-1a`, поэтому отказ зоны остановит всё. Нужны: второй сервер приложения в `public-b` (а лучше Auto Scaling Group в двух зонах), Application Load Balancer в `public-a` и `public-b` вместо Elastic IP, реплика базы в `private-b` с автоматическим переключением (проще всего RDS Multi-AZ), общее хранилище файлов вместо локального диска (S3), а при постоянном NAT - по шлюзу в каждой зоне. Подсети `public-b` и `private-b` для этого уже заложены в план адресов.

## Источники

1. Задание: [MSU-Courses/cloud-computing, Lab 03](https://github.com/MSU-Courses/cloud-computing/tree/main/Lab/03_Cloud_Networking).
2. Лекция 5 «Виртуальные сети в облаке. Amazon VPC», Hands-on 5.1.
3. [Amazon VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/): subnet sizing (reserved addresses), route tables, NAT gateways, network ACLs, security groups.
4. [Amazon Route 53 Developer Guide: private hosted zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html).
5. [Amazon EC2: Elastic IP addresses, AMIs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/), [AWS public IPv4 pricing](https://aws.amazon.com/vpc/pricing/).
6. [PostgreSQL 16: pg_hba.conf](https://www.postgresql.org/docs/16/auth-pg-hba-conf.html), [pg_dump](https://www.postgresql.org/docs/16/app-pgdump.html).
