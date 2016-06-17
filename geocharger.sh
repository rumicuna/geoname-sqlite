#!/bin/bash

GEONAMES="http://download.geonames.org/export/dump/"
POSTAL="http://download.geonames.org/export/zip/"

# Checking that sqlite is here
if [[ -z $( type -p sqlite3 ) ]]; then echo -e "REQUIRED: sqlite3 -- NOT INSTALLED !";exit ;fi

###############################################
# User choices and downloads
###############################################

# Country selection and download
echo "Enter the Country code (2 chars) you want to import"
echo "Or leave empty to import ALL countries"
read -p "Country to import ? [All] :" country
case ${country^^} in
  [A-Z][A-Z] ) COUNTRY="${country^^}";;
  "" ) COUNTRY="allCountries";;
  * ) echo "Unrecognized country ${country}"; exit;;
esac
echo "Trying to load the geolocalisation file..."
if wget -q -O "${COUNTRY}.zip" "${GEONAMES}${COUNTRY}.zip"
then
  echo "Downloaded ${COUNTRY} geolocalization file"
else
  echo "Unable to find ${COUNTRY}, aborting..."
  rm -f "${COUNTRY}.zip"
  exit
fi

# If all countries, we'll take the countries info
if [ ${COUNTRY} = "allCountries" ]
then
  echo "We need the country datas too, importing"
  if ! wget -q -O countryInfo.txt "${GEONAMES}countryInfo.txt"
  then
    echo "Cannot retrieve the coutries table"
    rm -f countryInfo.txt
    exit
  fi
fi

# Are postal codes required ?
while true; do
  read -p "Do you want the postal codes ? [y/N]" getpos
  case $getpos in
    [yY] ) withPostal=yes; break;;
    [nN] ) withPostal=no; break;;
  esac
done
if [ $withPostal = yes ]
then
  echo "Trying to load the postal codes file..."
  if wget -q -O "postal_${COUNTRY}.zip" "${POSTAL}${COUNTRY}.zip"
  then
    echo "Downloaded postal_${COUNTRY}"
  else
    echo "Unable to find ${COUNTRY}, sorry..."
    rm -f "postal_${COUNTRY}.zip"
    withPostal=no
    exit
  fi
fi

###############################################
# Extractions from zip files
###############################################
echo "Extracting geodatas..."
unzip -qq -o "${COUNTRY}.zip" "${COUNTRY}.txt"
mv "${COUNTRY}.txt" "geo_${COUNTRY}.txt"
rm -f "${COUNTRY}.zip"

if [ $withPostal = yes ]
then
  echo "Extracting postal codes..."
  unzip -qq -o "postal_${COUNTRY}.zip" "${COUNTRY}.txt"
  mv "${COUNTRY}.txt" "postal_${COUNTRY}.txt"
  rm -f "postal_${COUNTRY}.zip"
fi

###############################################
# Database creation and filling
###############################################
if [ -f geoloc.sqlite ]
then
  while true; do
    read -p "The database file already exists, overwriting ? [y/N]" overwrite
    case $overwrite in
      [yY] ) rm -rf geoloc.sqlite; break;;
      [nN] ) echo "Ok, so we leave the process..."; exit;;
    esac
  done
fi

echo "Creating and filling geonames table. Please wait"
sqlite3 geoloc.sqlite "create table geonames (geonameid INTEGER PRIMARY KEY, name TEXT, asciiname TEXT, alternatenames TEXT, latitude DECIMAL(10,7), longitude DECIMAL(10,7), fclass TEXT, fcode TEXT, country TEXT, cc2 TE$
sqlite3 geoloc.sqlite "create index country on geonames(country);"
sqlite3 geoloc.sqlite "create index names on geonames(name, asciiname, alternatenames);"
sed -i '/"/""/g' geo_${COUNTRY}.txt
echo -e ".separator \"\t\"\n.import geo_${COUNTRY}.txt geonames" | sqlite3 geoloc.sqlite

if [ ${COUNTRY} = 'allCountries' ]
then
  echo "Creating and importing countries informations"
  sqlite3 geoloc.sqlite "create table geocountry (iso_alpha2 TEXT PRIMARY KEY, iso_alpha3 TEXT, iso_numeric INTEGER, fips_code TEXT, name TEXT, capital TEXT, areainsqkm REAL, population INTEGER, continent TEXT, tld TEXT$
  sqlite3 geoloc.sqlite "create index iso_alpha3 on geocountry(iso_alpha3);"
  sed -i '/^#/d' countryInfo.txt
  echo -e ".separator \"\t\"\n.import countryInfo.txt geocountry" | sqlite3 geoloc.sqlite
fi

if [ $withPostal = yes ]
then
  echo "Creating and filling postal codes. Please wait"
  sqlite3 geoloc.sqlite "create table geozip (country TEXT, zipcode TEXT, name TEXT, statename TEXT, statecode TEXT, countyname TEXT, countycode TEXT, communame TEXT, commucode TEXT, latitude DECIMAL(10,7), longitude DE$
  sqlite3 geoloc.sqlite "create index zipcode on geozip(zipcode);"
  sqlite3 geoloc.sqlite "create index country on geozip(country);"
  sqlite3 geoloc.sqlite "create index name on geozip(name);"
  sed -i '/"/""/g' postal_${COUNTRY}.txt
  echo -e ".separator \"\t\"\n.import postal_${COUNTRY}.txt geozip" | sqlite3 geoloc.sqlite
fi

echo "All is filled for $COUNTRY"

###############################################
# Cleaning datas for smaller database ?
###############################################

read -p "Type N if you don't want to reduce the geonames to cities" reduce
if [ $reduce != N ]
then
  sqlite3 geoloc.sqlite "delete from geonames where fclass<>'P';"
fi

rm -f *${COUNTRY}* countryInfo.*
