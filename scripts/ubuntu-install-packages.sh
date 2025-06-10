
# returns 1 if the package was already installed and 0 otherwise. The first
# argument is the package name to be checked (and installed if not already).
# other arguments are passed to apt-get
maybe_install() {
    # $1 -- prefix to install
    # $2 -- package directory
    # $3 -- path to package
    pkgname=$(echo $3 | cut -d_ -f1);
    dpkg -l "$pkgname" 2>&1 | grep -q ^ii && return 1
    echo "installing $3"
    dpkg-deb -x "$2/$3" $1
    return 0
}

PREFIX=${HOME}/.local.ubuntu
PACKAGES_DIRECTORY="./"

mkdir -p ${PREFIX};

for pkg in $(ls); do 
  maybe_install ${PREFIX} ${PACKAGES_DIRECTORY} ${pkg}
done;
