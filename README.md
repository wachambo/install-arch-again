# Install Arch Again (a.k.a IAA)

## Installation
First of all connect to internet pluging ethernet cable or activating wifi with: `wifi-menu`

```
sh <(curl -fLs https://goo.gl/2EJPMa)
vi iaa.conf pkglist.txt
./iaa.sh
```
Enjoy :)

## Optional
Add custom scripts to run at the end of installation

## Files
|File       |Meaning                   |
|-----------|--------------------------|
|iaa.sh     |Main script               |
|iaa.conf   |Configuration             |
|pkglist.txt|Packages                  |
|\*.sh      |Optional script           |
|root\_\*.sh|Optional scripts (as root)|
|\_\*.sh    |Omitted scripts           |
