# WordPress Docker Stack

GitHub-fähiger WordPress-Stack mit WordPress (Apache/PHP 8.3), MySQL 8, Redis 8, OPcache und vollständig per `.env` konfigurierbaren Traefik-Labels.

## Architektur

- `wordpress`: WordPress mit Apache und PHP 8.3
- `mysql`: MySQL 8, nur im internen Backend-Netzwerk
- `redis`: Redis 8 als Object Cache, nur im internen Backend-Netzwerk
- `proxy`: vorhandenes externes Docker-Netzwerk für Traefik
- `backend`: internes Docker-Netzwerk ohne externen Zugriff
- Apache `mod_remoteip`: stellt hinter Cloudflare und Traefik die echte Besucher-IP wieder her

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

Beim ersten Start wird das angepasste WordPress-Image gebaut:

```bash
docker compose config
docker compose up -d --build
```

Bei späteren normalen Starts reicht:

```bash
docker compose up -d
```

`--build` ist nur erforderlich, wenn sich das `Dockerfile`, `docker-entrypoint-realip.sh` oder andere in das Image eingebaute Dateien ändern. Änderungen an `.env` erfordern normalerweise keinen erneuten Image-Build.

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
TRAEFIK_SERVICE_NAME=wordpress-app
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

## Echte Client-IP hinter Cloudflare und Traefik

Die Request-Kette ist typischerweise:

```text
Besucher -> Cloudflare -> Traefik -> WordPress/Apache
```

Ohne zusätzliche Konfiguration sieht Apache nur die IP-Adresse des vorgeschalteten Traefik-Containers. Der Stack aktiviert deshalb Apache `mod_remoteip` und verwendet den von Cloudflare gesetzten Header `CF-Connecting-IP`.

Die vertrauenswürdigen Proxy-Adressen werden in `.env` als kommaseparierte Liste angegeben. IPv4 und IPv6 können gemeinsam verwendet werden:

```dotenv
TRUSTED_PROXIES=172.31.191.254,fd00:1:be:a:7001:0:3e:7fff
```

Beim Containerstart erzeugt `docker-entrypoint-realip.sh` daraus für jede Adresse eine eigene Apache-Direktive:

```apache
RemoteIPTrustedProxy 172.31.191.254
RemoteIPTrustedProxy fd00:1:be:a:7001:0:3e:7fff
```

Auch CIDR-Netze können eingetragen werden, beispielsweise:

```dotenv
TRUSTED_PROXIES=172.31.128.0/18,fd00:1:be:a:7001:0:3e:7000/116
```

Aus Sicherheitsgründen sollten nur tatsächlich vertrauenswürdige Traefik-Adressen bzw. möglichst eng gefasste Docker-Netze eingetragen werden. Andernfalls könnte ein nicht vertrauenswürdiger Client versuchen, den `CF-Connecting-IP`-Header zu manipulieren.

Nach der Verarbeitung durch `mod_remoteip` enthält Apache `%a` die echte Besucher-IP. PHP und WordPress erhalten diese ebenfalls über `REMOTE_ADDR`.

Prüfen kannst du das über:

```bash
docker compose logs -f wordpress
```

Nach einer erstmaligen Aktivierung oder Änderung am Dockerfile/EntryPoint:

```bash
docker compose up -d --build
```

Änderst du später lediglich `TRUSTED_PROXIES` in `.env`, reicht normalerweise:

```bash
docker compose up -d
```

Compose erstellt den WordPress-Container bei geänderter Environment-Konfiguration neu und das EntryPoint-Script generiert die Apache-Proxy-Konfiguration beim Start erneut.

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

Neue Basis-Images herunterladen und das eigene WordPress-Image neu bauen:

```bash
docker compose pull
docker compose build --pull wordpress
docker compose up -d
docker image prune
```

Vor Updates sollte ein getestetes Backup vorhanden sein.

## Sicherheit

- `.env` ist über `.gitignore` vom Repository ausgeschlossen.
- MySQL und Redis besitzen keine veröffentlichten Host-Ports.
- Das Backend-Netzwerk ist als `internal` markiert.
- Nur WordPress hängt zusätzlich im externen Traefik-Netzwerk.
- `CF-Connecting-IP` wird nur über explizit konfigurierte vertrauenswürdige Proxies akzeptiert.
- Datenbankpasswörter gehören ausschließlich in die lokale `.env`.
- Für Produktion sollten regelmäßige Backups und Wiederherstellungstests eingerichtet werden.
