# Reading Jarvis in Obsidian

Obsidian opens your private vault, `jarvis-vault`, and keeps it in sync with GitHub through the Git community plugin. The vault folder is the repository's own root, which is what lets the plugin sync on both desktop and phone.

## Desktop

1. Clone your private vault, or use the `jarvis-vault/` folder from `DEPLOY.md` step A3.
2. In Obsidian: **Open folder as vault** and select `jarvis-vault`.
3. Settings > Community plugins > Browse: install and enable **Git**.
4. In the plugin settings:
   - turn on **pull on startup**;
   - set an automatic **pull** interval, for example 5 minutes;
   - set an automatic **commit-and-sync** interval too, so notes you edit by hand (such as ticking a task) reach GitHub and Jarvis sees them.

   Setting names can differ slightly between plugin versions.
5. Optional: Settings > Files and links > Default location for new notes > "In the folder specified below" > `inbox`.

## Phone

Mobile sync is not tested yet. Try it once before relying on it.

1. On GitHub, create a **fine-grained personal access token**: Settings > Developer settings > Personal access tokens > Fine-grained tokens. Set repository access to **Only select repositories** > your private `jarvis-vault`, and the **Contents** permission to **Read and write**.
2. Install Obsidian, create an empty vault, then install and enable the **Git** plugin.
3. Run the plugin's command **Clone an existing remote repo** with `https://github.com/<your-github-user>/jarvis-vault.git`, cloning into the vault root (not a subfolder). Sign in with your GitHub username and the token as the password.
4. Set the same pull interval as on desktop.

Treat the token like a password: it can read and change your notes.

## Settings

`settings.md` in the vault holds your time zone and home currency, and Obsidian shows them as **Properties** you can edit. Editing there works, but `/setup` checks the values for you. After changing the time zone, run `sudo timedatectl set-timezone <zone>` on the server as well.

## Excluded files

`.obsidian/app.json` in the vault excludes `templates/`, so the empty template notes stay out of search, the quick switcher, the graph, and link suggestions. They still show in the file list. Change the list under Settings > Files and links > Excluded files.
