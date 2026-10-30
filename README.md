# Talking Studio for iPhone

The studio from your PC, as a native iPhone app: paste or load a script, pick a voice (or use your own recording), and your hooded character reads it with gestures and captions. Free pictures from Wikimedia Commons, NASA and the Cleveland Museum of Art can be shown behind the character, with a credits file. Videos are saved to Photos and to the Files app (Talking Studio folder).

You do not need a Mac. GitHub builds the app for you on one of its Macs and gives you an `.ipa` file to download.

## 1. Put the project on GitHub (once)

1. Make a free account at https://github.com and create a **new repository** (any name, for example `talking-studio`). Choose **Public**: GitHub's cloud Macs are free for public repositories (private ones use a small monthly allowance and each build costs about 10x its minutes).
2. Upload the files (no extra software needed): on the new empty repository page click **uploading an existing file**, open `F:\TalkingCharacterIOS` in File Explorer, select everything inside it (`Sources`, `.github`, `project.yml`, `README.md`, `.gitignore`) and drag it into the browser. Check that the list shows `.github/workflows/build-ipa.yml`, then press **Commit changes**.
   * If `.github` did not upload (some browsers skip folders that start with a dot): on the repository page choose **Add file > Create new file**, type `.github/workflows/build-ipa.yml` as the name (typing the slashes makes the folders), paste in the contents of that file from your PC, and commit.
   * If you prefer Git on your PC: install Git for Windows, then run `git init`, `git add .`, `git commit -m "Talking Studio"`, `git branch -M main`, `git remote add origin https://github.com/YOUR-NAME/talking-studio.git` and `git push -u origin main`.

## 2. Build the IPA

1. On your repository page, open the **Actions** tab. The build **Build unsigned IPA** starts by itself after the push. You can also start it with **Run workflow**.
2. Wait about 10 minutes for a green tick. Open the finished run and download the artifact **TalkingStudio-unsigned-ipa** (a zip with `TalkingStudio-unsigned.ipa` inside). Unzip it.
3. If the run is red, open it, download the artifact **build-log**, and send me the file or the last 60 lines. The code could not be compiled on this PC, so the first build may need a fix.

## 3. Sideload it onto your iPhone (Windows)

The IPA is unsigned on purpose. A sideloading tool signs it with your own Apple ID.

1. Install **iTunes** and **iCloud** from Apple's website (not the Microsoft Store versions), then **Sideloadly** from https://sideloadly.io.
2. Plug in your iPhone, tap Trust, open Sideloadly, drag in `TalkingStudio-unsigned.ipa`, enter your Apple ID and press Start.
3. On the iPhone: Settings > Privacy & Security > turn on **Developer Mode** (iOS 16 and later, needs a restart), then Settings > General > VPN & Device Management > trust your Apple ID.
4. A free Apple ID app expires after **7 days** (re-run Sideloadly to refresh it) and you can have 3 sideloaded apps at once. AltStore is an alternative that can refresh the app over Wi-Fi.

## Using the app

* **Script:** paste, load a .txt/.md, or press Example. `# Title` shows a chapter banner, `*word*` highlights a word, `[point] [think] [happy]` and the other tags control gestures and eyes, `[idea]` shows a lightbulb, `[image: roman forum]` picks the picture to search for, `[noimage]` keeps the studio background.
* **Voice:** the voices built into iOS. For nicer ones, download an Enhanced or Premium voice in Settings > Accessibility > Spoken Content > Voices. Or turn on *Use my own recording* and pick an audio file (the script text must match what is said).
* **Pictures:** automatic picks from three free libraries. Only commercial-use-friendly licences are used (CC0, public domain, CC BY). A credits file is saved with the video; paste it into the video description.
* **Make the video:** keep the app open and the screen on until it finishes. Preview 12 s first to check the look. Full HD is slower and makes bigger files.

## Differences from the PC version

* iOS voices instead of the online AI voices.
* Pictures: Wikimedia Commons, NASA and the Cleveland Museum of Art only, picked automatically (no review screen, no Pexels/Pixabay/Unsplash keys yet).
* Shorter list of options. Same character, gestures, captions and timing logic.

## If something is wrong

Tell me what you saw (a screenshot or the build log) and I will fix it. The first build is the most likely place for a problem, because I could not compile Swift on Windows.
