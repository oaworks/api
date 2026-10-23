

# API Server Setup Scripts

These scripts provision a Linux server and install the OA.Works API and its
optional OpenSearch service. Run them from the repository root, or provide the
repository `scripts/` path explicitly. This provides a dev version of the API, 
not configured for production work, and without access to any secret keys etc.

## Typical Setup

1. **Create a server (optional).** Run `create_droplet.sh` to create a
	 DigitalOcean Droplet. If you already have a Linux server to use, you can 
   skip this step. You will need at least 2GB for dev, ideally 4GB (esp. 
	 if installing OpenSearch); 1 or 2 vCPU; about 2GB of disk for fixtures 
	 downloads (test data); about 5GB for indexes if installing OpenSearch. 
2. **Configure the server (recommended).** Run `configure_vm.sh` to create the
	 `oaw` account and choose server hardening, firewall, and baseline software
	 settings. You can instead confirm local configuration when running it on
	 the server itself. It also clones this repository into `~/api` on the
	 `develop` branch. If you configure the server yourself instead, create the
	 `oaw` account with passwordless sudo and SSH access, then clone the
	 repository and check out `develop`:

	 ```bash
	 git clone https://github.com/oaworks/api.git ~/api
	 cd ~/api && git checkout develop
	 ```

	 The remote (`--ip`) runs of the later scripts expect it at `~/api`.
3. **Install the API.** Run `install_oaworks_api.sh` to install dependencies
	 and build the API in the existing clone. Starting it and
	 opening the port are optional flags.
4. **Install OpenSearch (optional).** Run `install_opensearch.sh` if the API
	 needs a local search service. The installer binds OpenSearch to
	 `127.0.0.1:9200`; configure the API to use that address separately.

The scripts can be run remotely from a machine with SSH access, or locally on
the Linux server. Remote runs require a usable SSH key and the expected account
access. `configure_vm.sh` connects as `oaw` if that account already has SSH
and passwordless sudo access, and otherwise as `root`; the API and OpenSearch
installers connect as `oaw`.

## Requirements and Credentials

- Use Bash. Remote setup also requires an SSH client and network access to the
	target server.
- Droplet creation requires `curl`, `jq`, a DigitalOcean API token, and access
	to the account's SSH keys. The script prompts for a token if `--token` is
	omitted. Treat the token as a secret: do not commit it or paste it into
	shared command history. Use your team credential process.
- Droplet creation and remote configuration use SSH keys. A DigitalOcean key
	attached to a Droplet must match a private key available to the operator.
- The API installer downloads dependencies and builds the project. It does
	not configure production secrets or credentials for live services.

## `create_droplet.sh`

Creates an Ubuntu 24.04 x64 DigitalOcean Droplet, attaches the selected
DigitalOcean account SSH keys, waits for a public IP, and checks for SSH
availability. SSH keys are selected interactively from the account; if the
account has no keys, the script can offer to upload a local public key.

| Option | Description |
| --- | --- |
| `-t`, `--token <token>` | DigitalOcean API token. If omitted, the script prompts. |
| `-m`, `--memory <GB>` | Memory size: `4`, `8`, `16`, `32`, `64`, `128`, `192`, or `256`. Default: `4`. |
| `-d`, `--disk <multiplier>` | Disk multiplier: `1x`, `3x`, or `6x` for sizes with at least 16 GB RAM. Default: `1x`. For 4 or 8 GB, only `1x` is used. |
| `-n`, `--name <name>` | Droplet name. Default: `local` followed by the current timestamp. |
| `-k`, `--key <private-key>` | Local private key used to test SSH access to the new Droplet. If omitted, the script prompts and may suggest a key. |
| `-r`, `--region <slug>` | DigitalOcean region slug. Default: `nyc1`. The selected region must support the chosen size. |
| `-h`, `--help` | Show usage. |

Example (the token and SSH-key selection are still interactive):

```bash
bash scripts/create_droplet.sh --memory 4 --name api-server
```

On success, the script prints the Droplet ID and public IP and confirms SSH is
reachable. It does not run the other setup scripts automatically.

## `configure_vm.sh`

Prepares a Linux server for typical API use. In remote mode it connects as
`root`; in local mode it uses `sudo` as needed. It creates the requested user
(default `oaw`), grants passwordless sudo, clones the public API repository
into that user's `~/api` (on the `develop` branch) if not already present, and
offers to configure SSH access,
UFW, the timezone, unattended security upgrades, and baseline packages. The
package set includes build tools, Nginx, 1Password CLI, Certbot, Node.js 20,
and PM2.

| Option | Description |
| --- | --- |
| `-i`, `--ip <address>` | Configure this remote server. If omitted, Linux prompts to configure the current machine locally; macOS requires a target IP. |
| `-u`, `--user <name>` | Account to create and configure. Default: `oaw`. |
| `-k`, `--key <private-key>` | SSH private key for the remote connection. If omitted, the script prompts and may suggest a key. |
| `-h`, `--help` | Show usage. |

The script asks separately whether to disable root SSH and password
authentication, enable UFW with inbound ports 22, 80, and 443, set the timezone
to `Europe/London`, enable unattended upgrades, and install the baseline
packages. These prompts default to **Yes**. Password authentication is only
offered for disabling when it is currently enabled. Review the choices
carefully, especially firewall and SSH changes, before accepting them.

Example for a newly created Droplet:

```bash
bash scripts/configure_vm.sh --ip <DROPLET_IP> --key ~/.ssh/id_ed25519
```

On success, the script verifies access as the configured user and prints an
SSH command. It is safe to rerun: if the user already exists with SSH and
passwordless sudo access, the script connects as that user instead of `root`
and applies any remaining configuration, such as the API clone.

## `install_oaworks_api.sh`

Builds the API in the repository clone the script is run from (`~/api` for
remote runs), on whatever branch is checked out. It does not clone, pull, or
switch branches; update the clone with `git` first if needed. It installs
Node.js and required document utilities when needed, runs `npm install`, and
builds the API. By default, it builds but does not start the API.

| Option | Description |
| --- | --- |
| `-i`, `--ip <address>` | Install on a remote server by connecting as `oaw`. If omitted, prompts to install on the current machine. |
| `-k`, `--key <private-key>` | SSH private key for the remote connection. If omitted, the script prompts and may suggest a key. |
| `-s`, `--start-api` | Start the API after building and check for a response at `http://localhost:4000`. |
| `-e`, `--expose-api-port` | After a successful start, allow inbound TCP port 4000 with UFW. Requires UFW on Linux; this does not open a port on macOS. |
| `--api-public-ip <address>` | Include a public API URL in the completion output when the API starts and its port is opened. Defaults to the `--ip` address for remote runs. This reports an address; it does not configure DNS, TLS, or the API's bind address. |
| `-h`, `--help` | Show usage. |

Example to build, start, and open port 4000 on a configured server:

```bash
bash scripts/install_oaworks_api.sh --ip <DROPLET_IP> --start-api --expose-api-port
```

The API is considered started only if it responds locally on port 4000. The
installer does not set up production secrets, live-service access, or a
process manager configuration.

## `install_opensearch.sh`

Downloads and configures a single-node OpenSearch instance, adjusts its JVM
heap and Linux `vm.max_map_count` setting where applicable, and installs a
service that starts at boot. It uses `systemd` on Linux and `launchd` on
macOS, then checks whether OpenSearch responds on port 9200.

| Option | Description |
| --- | --- |
| `-i`, `--ip <address>` | Install on a remote server by connecting as `oaw`. If omitted, prompts to install on the current machine. |
| `-k`, `--key <private-key>` | SSH private key for the remote connection. If omitted, the script prompts and may suggest a key. |
| `-n`, `--name <name>` | OpenSearch cluster name. Default: `idx_YYYYMMDD`. |
| `-v`, `--version <version>` | OpenSearch release to install. If omitted, prompts with default `2.9.0`. |
| `-d`, `--dir <path>` | Installation directory. Default: `$HOME/opensearch`. |
| `-p`, `--data-dir <path>` | Separate data directory. If omitted, OpenSearch uses its packaged default data directory. |
| `-h`, `--help` | Show usage. |

The installer also prompts for JVM heap size; the suggested value is based on
half the detected RAM, capped at 31 GB. If a custom data directory does not
exist, it asks whether to create it.

Example:

```bash
bash scripts/install_opensearch.sh --ip <DROPLET_IP> --key ~/.ssh/id_ed25519 --version 2.9.0
```

OpenSearch is configured with security disabled and binds only to
`127.0.0.1:9200`. Do not expose this service directly to an untrusted
network. The API must be configured separately to use `localhost:9200` on the
same server.


## Getting test data fixtures

Fixtures are JSON Lines dumps of a set of API indexes, which can be loaded into
a development API's OpenSearch to give it realistic test data.

> **Note:** These scripts work on the API clone at `~/api`. Run them on the VM
> itself, or from your own machine with `-i <DROPLET_IP>` to run them there
> over SSH as `oaw`. With `-i`, pass `-k <private-key>` or choose a key when
> prompted. Without `-i`, each script first asks you to confirm running on the
> local machine.

Before loading fixtures, the VM needs:

- The API installed (`install_oaworks_api.sh`) and running from `~/api` with
  `npm run start`, which uses `node --watch` so rebuilds reload it
  automatically.
- The API running in development mode, as the load route refuses to run otherwise.
- OpenSearch installed (`install_opensearch.sh`) and the API configured to use
  it at `localhost:9200` (or configure your API settings to point at a remote hosted index.)
- `curl` and `jq`.

### 1. Download fixtures: `get_fixtures.sh`

Downloads the latest finished fixture dump into `~/api/fixtures`, creating the
folder if needed and overwriting any existing files. It reads
`/fixtures/_meta.json` from the source, then retrieves that file and one
`<index>.jsonl` file per index listed in it.

| Option | Description |
| --- | --- |
| `-u`, `--url <base_url>` | Base URL to fetch `/fixtures` from. Default: `https://static.oa.works`. |
| `-i`, `--ip <address>` | Run on this remote server as `oaw`, in `~/api`. |
| `-k`, `--key <private-key>` | SSH private key for `--ip`. If omitted, the script prompts and may suggest a key. |
| `-h`, `--help` | Show usage. |

```bash
cd ~/api
bash scripts/get_fixtures.sh
```

If `_meta.json` is missing or the dump has no `finished` value, the script
reports that no fixtures are available and exits without downloading. In that
case, rerun it with `--url` pointing at an API instance that has already
generated fixtures. You can also put `.jsonl` files into `~/api/fixtures`
yourself instead of using this script.

As a last resort, if the API at the URL you are trying to get fixtures from 
seems to not complete creating fixtures, there is a ?clear option that can be 
added to the fixtures URL to try to force it to start again.

### 2. Load fixtures: `load_fixtures.sh`

Loads every `.jsonl` file in `~/api/fixtures` into the index of the same name,
for example `report_orgs.jsonl` into `report_orgs` (using any locally configured 
prefixes as appropriate).

| Option | Description |
| --- | --- |
| `-u`, `--url <trigger_url>` | Full load trigger URL. Default: `http://localhost:4000/fixtures/load?trigger`. |
| `-i`, `--ip <address>` | Run on this remote server as `oaw`, in `~/api`. The URL is then requested from that server. |
| `-k`, `--key <private-key>` | SSH private key for `--ip`. If omitted, the script prompts and may suggest a key. |
| `-h`, `--help` | Show usage. |

```bash
cd ~/api
bash scripts/load_fixtures.sh
```

After you confirm the load prompt (default **Yes**), the script:

1. Copies `scripts/fixtures_load.coffee` into `server/src` and runs
   `npm run build`.
2. Waits for the API to restart with the new build.
3. Sends the trigger request and waits for the load to finish, then prints the
   JSON response with the record count per index.
4. Removes the injected file and runs `npm run build` again. This cleanup also
   runs if any earlier step fails.

If there are no files in `~/api/fixtures`, the script exits and asks you to run
`get_fixtures.sh` or populate the folder first. If the API does not come back
with the fixtures code within about a minute, check that it is running with
`npm run start`.

Fixtures are currently about 2GB in total.

### Side note: Generating fixtures

It is also possible to generate fixtures from your current local dev instance. 
The /fixtures endpoint triggers it, however it also requires a local setting 
for a static files folder, so add .static.folder to your settings.json or 
server.json file and rebuild the API codebase. Passing the ?trigger param 
causes the fixtures dump to run. You can then send / rsync / do whatever 
you want with the local generated fixtures, such as to bootstrap another 
dev machine with whatever current data state you have locally.


## Running Tests

Use `run_tests.sh` to run the API's test runner against a JSON Lines file in
`fixtures/`. The API must already be running on the execution machine at
`http://localhost:4000`, with any data and services required by the tests
configured and available. Run the API from the repository root so it can find
the fixtures there.

The supplied `fixtures/test.jsonl` contains one JSON object per line, with test
identifiers, endpoint URLs, parameters, and expected response fields. Its
current tests target `http://localhost:4000/report/works`. You can add other
test files to `fixtures/`, such as `test_permissions.jsonl`: filenames must
start with `test` and end with `.jsonl`. Use JSON Lines, not CSV or TSV, and
follow the existing test file's record format.

| Option | Description |
| --- | --- |
| `-i`, `--ip <address>` | Run on this remote server as `oaw`, in `~/api`. Test files must exist in that server's `~/api/fixtures`. |
| `-k`, `--key <private-key>` | SSH private key for `--ip`. If omitted, choose a numbered key, accept the suggested default, or enter a path. |
| `-t`, `--test-file <filename>` | Test filename only, for example `test.jsonl`, not a path. If omitted or invalid, choose an available file by number or filename. |
| `-h`, `--help` | Show usage. |

To run the supplied tests locally:

```bash
cd ~/api
bash scripts/run_tests.sh --test-file test.jsonl
```

Without `--ip`, the script asks for a target IP. Leave it blank and answer
**Yes** to the local-run confirmation (default **No**). Omit `--test-file` to
see and select from the available `test*.jsonl` files. If none exist, download
them with `get_fixtures.sh` or create a suitable file first.

To run on a configured VM:

```bash
bash scripts/run_tests.sh --ip <DROPLET_IP> --key ~/.ssh/id_ed25519 --test-file test.jsonl
```

The remote run selects and reads files on the VM, not your local machine. The
script sends the filename as the `sheet` query parameter to
`http://localhost:4000/test`, waits for the response, and prints it. For a
remote run, `localhost` is the VM itself.

NOTE: the oa.works project has extensive tests in a google sheet which can also be run directly 
from that sheet, or imported, in various ways that are not yet covered here. Just a note 
before anyone goes spending lots of time writing new tests - there may be plenty 
already available elsewhere! So check with someone in the team first.

### Reviewing Results

Each successful request saves the JSON response in `results/` beside the
repository's `scripts/` folder, creating it if needed. Result filenames use
the test filename without `.jsonl` plus a timestamp, for example
`test_20261008_143025.json`. Remote runs add a unique suffix to identify the
result when copying it back.

Open the saved JSON to review the test runner's output and compare runs, or
format a selected result in the terminal:

```bash
ls -lt results/
jq . results/test_20261008_143025.json
```

Remote runs save results in the VM's `~/api/results/`. After completion, the
script asks whether to save that result locally too (default **No**). Answer
**Yes** to copy it into your local clone's `results/` using the same SSH key;
the remote copy is retained.

