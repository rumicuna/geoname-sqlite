#!/bin/bash

GEONAMES="http://download.geonames.org/export/dump/"
POSTAL="http://download.geonames.org/export/zip/"

R='\033[0;31m'
G='\033[0;32m'
B='\033[0;34m'
NC='\033[0m'

# Checking that sqlite is here
if [[ -z $( type -p sqlite3 ) ]]; then echo -e "REQUIRED: sqlite3 -- NOT INSTALLED !";exit ;fi

###############################################
# User choices and downloads
###############################################

# Country selection and download
echo "Enter the Country code (2 chars) you want to import"
echo "Or leave empty to import ALL countries"
read -p "Country to import ? [All] : " country
case ${country^^} in
  [A-Z][A-Z] ) COUNTRY="${country^^}";;
  "" ) COUNTRY="allCountries";;
  * ) echo -e "Unrecognized country ${B}${country}${NC}"; exit;;
esac

if [ -f geo_${COUNTRY}.txt ]
then
  echo -e "${R}Warning${NC}: geo_${COUNTRY}.txt already exists"
  while true; do
    read -p "Download it again ? [y/N] : " yn
    case $yn in
      [yY] ) dl=yes; break;;
      [nN] ) dl=no; break;;
    esac
  done
else
  dl=yes
fi
if [ $dl = "yes" ]
then
  echo "Trying to load the geolocalisation file..."
  if wget -q -O "${COUNTRY}.zip" "${GEONAMES}${COUNTRY}.zip"
  then
    echo "Downloaded ${COUNTRY} geolocalization file"
  else
    echo "Unable to find ${COUNTRY}, aborting..."
    rm -f "${COUNTRY}.zip"
    exit
  fi

  echo "Extracting geodatas..."
  unzip -qq -o "${COUNTRY}.zip" "${COUNTRY}.txt"
  mv "${COUNTRY}.txt" "geo_${COUNTRY}.txt"
  rm -f "${COUNTRY}.zip"
fi

# If all countries, we'll take the countries info
if [ ${COUNTRY} = "allCountries" ]
then
  if [ -f countryInfo.txt ]
  then
    echo -e "${R}Warning${NC}: countryInfo.txt already exists"
    while true; do
      read -p "Download it again ? [y/N] : " yn
      case $yn in
        [yY] ) dl=yes; break;;
        [nN] ) dl=no; break;;
      esac
    done
  else
    dl=yes
  fi
  if [ $dl = yes ]
  then 
    echo "We need the country datas too, importing"
    if ! wget -q -O countryInfo.txt "${GEONAMES}countryInfo.txt"
    then
      echo "Cannot retrieve the coutries table"
      rm -f countryInfo.txt
      exit
    fi
  fi
fi

# Are postal codes required ?
while true; do
  read -p "Do you want the postal codes ? [y/N] : " getpos
  case $getpos in
    [yY] ) withPostal=yes; break;;
    [nN] ) withPostal=no; break;;
  esac
done
if [ $withPostal = yes ]
then
  if [ -f postal_${COUNTRY}.txt ]
  then
    echo -e "${R}Warning${NC}: postal_${COUNTRY}.txt already exists"
    while true; do
      read -p "Download it again ? [y/N] : " yn
      case $yn in
        [yY] ) dl=yes; break;;
        [nN] ) dl=no; break;;
      esac
    done
  else
    dl=yes
  fi
  if [ $dl = yes ]
  then
    echo "Trying to load the postal codes file..."
    if wget -q -O "postal_${COUNTRY}.zip" "${POSTAL}${COUNTRY}.zip"
    then
      echo "Downloaded postal_${COUNTRY}, now extracting"
	  unzip -qq -o "postal_${COUNTRY}.zip" "${COUNTRY}.txt"
      mv "${COUNTRY}.txt" "postal_${COUNTRY}.txt"
      rm -f "postal_${COUNTRY}.zip"
    else
      echo "Unable to find ${COUNTRY}, sorry..."
      rm -f "postal_${COUNTRY}.zip"
      withPostal=no
    fi
  fi
fi

###############################################
# Database creation and filling
###############################################
dba=no
if [ -f geoloc.sqlite ]
then
  echo -e "${R}Warning${NC}: The database file already exists... \c"
  dba=yes
  while true; do
    read -p "overwrite, append or stop ? [O/a/s] : " overwrite
    case $overwrite in
      [oO] ) rm -rf geoloc.sqlite; dba=no; break;;
      [aA] ) break;;
      [sS] ) echo "Leaving process..."; exit;;
    esac
  done
fi
if [ $dba = no ]
then
  echo "Creating database"
  sqlite3 geoloc.sqlite "create table geonames (geonameid INTEGER, name TEXT, asciiname TEXT, alternatenames TEXT, latitude DECIMAL(10,7), longitude DECIMAL(10,7), feature_class TEXT, feature_code TEXT, country TEXT, cc2 TEXT, admin1_code TEXT, admin2_code TEXT, admin3_code TEXT, admin4_code TEXT, population INTEGER, elevation INTEGER, dem INTEGER, timezone TEXT, modification_date TEXT);"
  sqlite3 geoloc.sqlite "create index country on geonames(country);"
  sqlite3 geoloc.sqlite "create index names on geonames(name, asciiname, alternatenames);"
  sqlite3 geoloc.sqlite "create table geocountry (iso_alpha2 TEXT PRIMARY KEY, iso_alpha3 TEXT, iso_numeric INTEGER, fips_code TEXT, name TEXT, capital TEXT, areainsqkm REAL, population INTEGER, continent TEXT, tld TEXT, currency TEXT, currencyName TEXT, Phone TEXT, postalCodeFormat TEXT, postalCodeRegex TEXT, geonameId INTEGER, languages TEXT, neighbours TEXT, equivalentFipsCode TEXT);"
  sqlite3 geoloc.sqlite "create index iso_alpha3 on geocountry(iso_alpha3);"
  sqlite3 geoloc.sqlite "create table geozip (country TEXT, zipcode TEXT, name TEXT, statename TEXT, statecode TEXT, countyname TEXT, countycode TEXT, communame TEXT, commucode TEXT, latitude DECIMAL(10,7), longitude DECIMAL(10,7), accuracy INTEGER);"
  sqlite3 geoloc.sqlite "create index zipcode on geozip(zipcode);"
  sqlite3 geoloc.sqlite "create index zipcountry on geozip(country);"
  sqlite3 geoloc.sqlite "create index zipnames on geozip(name);"
fi

echo -e "Filling geonames table"
IFS=' ' read l n <<<"$(wc -l geo_${COUNTRY}.txt)"
if [ $l > 100000 ]
then
  split -l 100000 --additional-suffix=.txt geo_${COUNTRY}.txt gsplit
  # total=$(ls -l gsplit* | wc -l)
  for f in gsplit*.txt; do
    echo -e "parsing ${B}$f${NC}"
    sed -i 's/"/""/g;s/[^\t]*/"&"/g' $f
    echo -e ".separator \"\t\"\n.import $f geonames" | sqlite3 geoloc.sqlite
  done
  rm -rf gsplit*.txt
else
  sed -i 's/"/""/g;s/[^\t]*/"&"/g' geo_${COUNTRY}.txt
  echo -e ".separator \"\t\"\n.import geo_${COUNTRY}.txt geonames" | sqlite3 geoloc.sqlite
fi

if [ ${COUNTRY} = 'allCountries' ]
then
  echo "Creating and importing countries informations"
  sed -i '/^#/d' countryInfo.txt
  echo -e ".separator \"\t\"\n.import countryInfo.txt geocountry" | sqlite3 geoloc.sqlite
fi

if [ $withPostal = yes ]
then
  echo "Creating and filling postal codes. Please wait"
  IFS=' ' read l n <<<"$(wc -l postal_${COUNTRY}.txt)"
  if [ $l > 100000 ]
  then
    split -l 100000 --additional-suffix=.txt postal_${COUNTRY}.txt psplit
    for f in psplit*.txt; do
      sed -i 's/"/""/g;s/[^\t]*/"&"/g' $f
      echo -e "parsing ${B}$f${NC}"
      echo -e ".separator \"\t\"\n.import $f geozip" | sqlite3 geoloc.sqlite
    done
    rm -rf psplit*.txt
  else
    sed -i 's/"/""/g;s/[^\t]*/"&"/g' postal_${COUNTRY}.txt
    echo -e ".separator \"\t\"\n.import postal_${COUNTRY}.txt geozip" | sqlite3 geoloc.sqlite
  fi
fi

echo "All is filled for $COUNTRY"

###############################################
# Cleaning datas for smaller database ?
###############################################

#read -p "Type N if you don't want to reduce the geonames to cities " reduce
#if [ "$reduce" != "N" ]
#then
#  sqlite3 geoloc.sqlite "delete from geonames where fclass<>'P';"
#fi

# rm -f *${COUNTRY}* countryInfo.*
