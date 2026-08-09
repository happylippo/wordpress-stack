# WordPress Docker Stack

GitHub-fähiger WordPress-Stack mit WordPress (Apache/PHP 8.3), MySQL 8, Redis 8, OPcache und vollständig per `.env` konfigurierbaren Traefik-Labels.

## Architektur

- `wordpress`: WordPress mit Apache und PHP 8.3
- `mysql`: MySQL 8, nur im internen Backend-Netzwerk
- `redis`: Redis 8 als Object Cache, nur im internen Backend-Netzwerk
- `proxy`: vorhandenes externes Docker-Netzwerk für Traefik
- `backend`: internes Docker-Netzwerk ohne externen Zugriff

## Installation

```bash
git clone https://github.com/happylippo/wordpress-stack.git
cd wordpress-stack
cp .env.example .env
```

Erzeuge zwei unterschiedliche sichere Passwörter, beispielsweise mit:

```bash
openssl rand -base64 32
```

Trage sie in `.env` ein:

```dotenv
MYSQL_PASSWORD=CHANGE_ME_DATABASE_PASSWORD
MYSQL_ROOT_PASSWORD=CHANGE_ME_ROOT_PASSWORD
```

Passe anschließend mindestens die Domain an:

```dotenv
TRAEFIK_RULE=Host(`wordpress.example.com`)
```

Falls das externe Traefik-Netzwerk noch nicht existiert:

```bash
docker network create proxy
```

Stack prüfen und starten:

```bash
docker compose config
docker compose up -d
```

Status und Logs:

```bash
docker compose ps
docker compose logs -f wordpress mysql redis
```

## Traefik

Alle Traefik-Labelwerte des WordPress-Containers werden über `.env` gesteuert:

```dotenv
TRAEFIK_ENABLE=true
TRAEFIK_DOCKER_NETWORK=proxy
TRAEFIK_ENTRYPOINTS=websecure
TRAEFIK_RULE=Host(`wordpress.example.com`)
TRAEFIK_SERVICE_NAME=wordpress
TRAEFIK_SERVICE_PORT=80
TRAEFIK_TLS=true
TRAEFIK_CERTRESOLVER=cloudflare_resolver
TRAEFIK_MIDDLEWARES=security-headers@file
TRAEFIK_PASS_HOST_HEADER=true
```

Mehrere Middlewares können kommasepariert angegeben werden:

```dotenv
TRAEFIK_MIDDLEWARES=security-headers@file,crowdsec@file
```

Die Compose-Konfiguration setzt außerdem `FORCE_SSL_ADMIN` und berücksichtigt `X-Forwarded-Proto`, damit WordPress HTTPS hinter Traefik korrekt erkennt.

## Redis Object Cache

WordPress erhält bereits die Redis-Verbindungsparameter über `WORDPRESS_CONFIG_EXTRA`:

- Host: `redis`
- Port: `6379`
- Datenbank: konfigurierbar über `REDIS_DATABASE`

Installiere im WordPress-Backend anschließend das Plugin **Redis Object Cache** und aktiviere dort den Object Cache.

Redis ist nicht am Host veröffentlicht und ausschließlich über das interne Backend-Netzwerk erreichbar.

## OPcache

Die versionierte Konfiguration befindet sich in:

```text
config/php/opcache.ini
```

Sie wird read-only nach `/usr/local/etc/php/conf.d/10-opcache.ini` eingebunden.

Prüfen:

```bash
docker compose exec wordpress php -i | grep -i opcache
```

Nach Änderungen:

```bash
docker compose up -d --force-recreate wordpress
```

Die Standardwerte sind auf einen normalen WordPress-Produktivbetrieb ausgelegt. `opcache.validate_timestamps=1` bleibt aktiviert, damit Plugin-, Theme- und Core-Updates ohne manuelles Leeren des OPcache erkannt werden.

## PHP- und Upload-Limits

Die PHP-Limits befinden sich in:

```text
config/php/uploads.ini
```

Standardwerte:

- `upload_max_filesize=128M`
- `post_max_size=128M`
- `memory_limit=512M`
- `max_execution_time=300`
- `max_input_vars=5000`

Bei vorgeschalteten Proxys oder CDN-Diensten können zusätzliche Upload-Limits gelten.

## MySQL

Die wichtigsten Tuning-Werte sind über `.env` konfigurierbar:

```dotenv
MYSQL_INNODB_BUFFER_POOL_SIZE=256M
MYSQL_MAX_CONNECTIONS=100
```

Weitere statische Einstellungen liegen unter:

```text
config/mysql/custom.cnf
```

Der InnoDB Buffer Pool sollte passend zum verfügbaren RAM des Servers dimensioniert werden.

## Redis

Redis verwendet AOF-Persistenz und standardmäßig:

```dotenv
REDIS_MAXMEMORY=256mb
REDIS_MAXMEMORY_POLICY=allkeys-lru
```

Da Redis hier als Cache und nicht als primärer Datenspeicher verwendet wird, ist `allkeys-lru` für diesen Einsatzzweck sinnvoll.

## Updates

```bash
docker compose pull
docker compose up -d
docker image prune
```

Vor Updates sollte ein getestetes Backup vorhanden sein.

## Sicherheit

- `.env` ist über `.gitignore` vom Repository ausgeschlossen.
- MySQL und Redis besitzen keine veröffentlichten Host-Ports.
- Das Backend-Netzwerk ist als `internal` markiert.
- Nur WordPress hängt zusätzlich im externen Traefik-Netzwerk.
- Datenbankpasswörter gehören ausschließlich in die lokale `.env`.
- Für Produktion sollten regelmäßige Backups und Wiederherstellungstests eingerichtet werden.
