# Empire of Lords

Prototype Godot 4 (2D isométrique) — jeu de conquête 4X temps réel à nœuds, avec une méta-jeu compétitif infini (saisons, ligue, Top des Seigneurs, Royaumes, Alliances, Tournoi).

## Modes de jeu (menu au lancement)

- **Solo** — la campagne solo.
- **Multi VS** — parties rapides « à la volée » (salle d'attente + compte à rebours, saison courte).
- **Multi Conquête** — le tournoi/ligue, servi par un **serveur persistant** (le monde continue entre les sessions).

## Architecture multijoueur

Multijoueur **ENet natif de Godot** (aucun service externe). Le **serveur dédié** est le
peer 1 = autorité : il fait tourner le `GameState` et diffuse des snapshots aux clients ;
les clients envoient leurs commandes (lancement / amélioration / recrutement) via RPC.

Le serveur **Conquête est persistant** : il sauvegarde le monde dans
`user://conquest_world.json` (toutes les ~15 s + à l'arrêt) et le **recharge au démarrage**.
Chaque joueur qui se connecte reçoit sa propre capitale (ré-attribuée en cas de reconnexion).

### Composants clés

| Fichier | Rôle |
|---|---|
| `scenes/Lobby.tscn` + `scripts/lobby.gd` | Menu : Solo / Multi VS / Multi Conquête |
| `scenes/Room.tscn` + `scripts/room.gd` | Salle d'attente + chat + décompte (VS) |
| `scenes/Multiplayer.tscn` + `scripts/multiplayer_main.gd` | Monde partagé (hôte local ou client) |
| `scenes/server.tscn` + `scripts/server.gd` | **Serveur dédié persistant Conquête** (headless) |
| `scripts/lan_net.gd` | Autoload ENet (connexion, autorité peer 1) |
| `scripts/game_state.gd` | Simulation + sauvegarde/chargement du monde |

---

## 1. Héberger le code sur GitHub

Le dépôt git est déjà initialisé localement et tout est prêt. Pour le pousser sur GitHub :

```bash
# 1) Crée un dépôt vide sur github.com (sans README, sinon conflit)
# 2) Puis, dans le dossier du projet :
git add -A
git commit -m "Empire of Lords — prototype multijoueur avec serveur persistant"
git branch -M main
git remote add origin https://github.com/<TON_COMPTE>/empire-of-lords.git
git push -u origin main
```

> Je n'ai pas tes identifiants GitHub, donc l'authentification/le push se font de ton côté
> (installe [GitHub CLI](https://cli.github.com/) et fais `gh auth login`, ou utilise un
> token dans l'URL du remote).

## 2. GitHub Actions construit le serveur automatiquement

Dès que le code est poussé, le workflow `.github/workflows/build-server.yml` :
- installe Godot 4.7 headless,
- exporte le preset **« Linux Server »** (`export_presets.cfg`, mode `dedicated_server`),
- publie `empire_of_lords_server.x86_64` en **artefact** (et en **Release** si tu pousses un tag `v*`).

Récupère l'artefact dans **Actions → Build Server**, ou crée un tag pour avoir une Release :
```bash
git tag v1.0.0 && git push origin v1.0.0
```

## 3. Déployer le serveur persistant sur ton VPS Hostinger

Le serveur est un simple binaire Linux x86_64. Sur ton VPS (Ubuntu/Debian) :

```bash
# Télécharger l'artefact / Release sur le VPS (scp ou wget depuis GitHub Release)
scp empire_of_lords_server.x86_64 root@<IP_VPS>:/opt/empire/
ssh root@<IP_VPS>
cd /opt/empire
chmod +x empire_of_lords_server.x86_64

# Ouvrir le port UDP 7777 (pare-feu)
ufw allow 7777/udp
# (Sur l'interface Hostinger, ouvre aussi le port 7777 UDP dans le pare-feu réseau/VPS)

# Lancer (en arrière-plan)
nohup ./empire_of_lords_server.x86_64 --server --port 7777 > server.log 2>&1 &
```

### Service systemd (redémarrage auto + logs) — recommandé

Créer `/etc/systemd/system/empire-of-lords.service` :

```ini
[Unit]
Description=Empire of Lords persistent server
After=network.target

[Service]
WorkingDirectory=/opt/empire
ExecStart=/opt/empire/empire_of_lords_server.x86_64 --server --port 7777
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now empire-of-lords
journalctl -u empire-of-lords -f   # voir les logs du serveur
```

Le monde est sauvegardé dans `user://` = `~/.local/share/godot/app_userdata/Nouveau projet de jeu/conquest_world.json`
sur le VPS. Il **survit aux redémarrages** du serveur.

## 4. Rejoindre le serveur (côté joueur)

Chaque joueur lance le jeu (client), choisit **Multi Conquête**, puis **Rejoindre** avec :
- **IP du serveur** : l'IP publique du VPS
- **Port** : `7777`

Le joueur entre directement dans le monde partagé en cours (pas de salle d'attente).

> **Réseau** : le serveur utilise **UDP 7777** — ouvre bien ce port en UDP sur le VPS et
> dans le pare-feu Hostinger. Pour tester en local : `127.0.0.1:7777`.

## Développement local du serveur

```bash
# Depuis l'éditeur Godot (Windows/macOS/Linux), lancer le serveur headless :
godot --headless res://scenes/server.tscn -- --port 7777

# Test E2E (2 processus) :
#   A: godot --headless res://scenes/server.tscn -- --port 7777
#   B: godot --headless --script res://tests/persist_driver.gd -- --port=7777
```

## Tests

```bash
godot --headless -s res://tests/test_balance.gd        # tests d'équilibrage (3/3)
```
