#!/bin/bash

# wsczytywanie danoych do skryptu
if [[ $1 == "-h" || $1 == "--help" ]]
then
    echo "(help page)"
    echo 'podstawowe uzycie:'
    echo '$./meteo.sh "city_name"'
    echo
    echo 'pokazanie strony z pomoca:'
    echo '$./meteo.sh -h    or    $./meteo.sh --help'
    echo
    echo 'pokazywanie komunikatow o aktualnym dzialaniu programu:'
    echo '$./meteo.sh --debug "city_name"    or    $./meteo.sh --verbose "city_name"'
    exit 0
fi

debug=0
if [[ $1 == "--verbose" || $1 == "--debug" ]]
then
    debug=1
    homeCity=$2
elif [[ $2 == "--verbose" || $2 == "--debug" ]]
then
    debug=1
    homeCity=$1
else
    homeCity=$1
fi


cityCashPath='./cityCash.json'

if [[ $debug -eq 1 ]]
then
echo 'pobieranie danych z IMGW'
fi
meteoAPI=$(curl -s https://danepubliczne.imgw.pl/api/data/synop) # pobieranie danych od IMGW-PIB
if test -e $cityCashPath;
then
    cityCash=$(cat $cityCashPath)
else
    echo 'pierwsze uruchomienie potrwa ponad minute z powodu ograniczen nalozonych przez https://nominatim.org/'
    echo 'prosze o cierpliwosc :)'
    echo {} > $cityCashPath
fi



for ((i=0; i<=$(echo $meteoAPI | jq '. | length'); i++)); # pobieranie danych z api nominatim
do
    if [[ $i -eq $(echo $meteoAPI | jq '. | length') ]]
    then
        cityName=$homeCity
    else
        cityName=$(echo $meteoAPI | jq -r '.['$i'].stacja')
    fi

    if [[ $debug -eq 1 ]]
    then
    echo 'sprawdzanie cash dla '$cityName
    fi

    cityName=$(echo $cityName | iconv -f utf8 -t ascii//TRANSLIT | tr ' ' '_') #usuwanie polskich znakow i spacji z nazwy miasta

    cityData=$(echo $cityCash | jq -r '.'$cityName)
    if ! [[ -n $cityData && $cityData != 'null' ]]
    then
        if [[ $debug -eq 1 ]]
        then
        echo 'pobieranie i zapisanie danych z nominatim dla '$cityName
        fi
        cityGeometry=$(curl -s -L -H "User-Agent: Mozilla/5.0" "https://nominatim.openstreetmap.org/search?country=Poland&city='$cityName'&limit=1&format=geojson" | jq '.features[0].geometry')

        echo $cityGeometry > temp.json
        echo $(jq --argfile cityGeometry temp.json '.'$cityName' += $cityGeometry' $cityCashPath) > $cityCashPath
        rm temp.json

        sleep 1 # nominatim przyjmuje max 1 zapytanie na 1s
    fi
done


homeCity=$(echo $homeCity | iconv -f utf8 -t ascii//TRANSLIT) #usuwanie polskich znakow z nazwy miasta
homeCity=$(echo $homeCity | tr ' ' '_') #usuwanie spacji z nazwy miasta

inputx=$(cat cityCash.json | jq '.'$homeCity'.coordinates[0]')
inputy=$(cat cityCash.json | jq '.'$homeCity'.coordinates[1]')

shortCity=$(echo $meteoAPI | jq -r '.[0].stacja')

for ((i=0; i<$(echo $meteoAPI | jq '. | length'); i++)); # ustalenie najblizszego miasta
do
    shortCityPars=$(echo $shortCity | iconv -f utf8 -t ascii//TRANSLIT | tr ' ' '_') #usuwanie polskich znakow i spacji z nazwy miasta
    shortx=$(cat cityCash.json | jq '.'$shortCityPars'.coordinates[0]')
    shorty=$(cat cityCash.json | jq '.'$shortCityPars'.coordinates[1]')

    # obliczanie odleglosci od poprzedniego najblizszego miasta
    deltax=$(echo $inputx-$shortx | bc)
    deltay=$(echo $inputy-$shorty | bc)
    shortDist=$(echo $deltax*$deltax+$deltay*$deltay | bc)

    cityName=$(echo $meteoAPI | jq -r '.['$i'].stacja')
    cityNamePars=$(echo $cityName | iconv -f utf8 -t ascii//TRANSLIT | tr ' ' '_') #usuwanie polskich znakow i spacji z nazwy miasta
    
    cityx=$(cat cityCash.json | jq '.'$cityNamePars'.coordinates[0]')
    cityy=$(cat cityCash.json | jq '.'$cityNamePars'.coordinates[1]')

    # obliczanie odleglosci od miasta
    deltax=$(echo $inputx-$cityx | bc)
    deltay=$(echo $inputy-$cityy | bc)
    cityDist=$(echo $deltax*$deltax+$deltay*$deltay | bc)

    if [[ $debug -eq 1 ]]
    then
    echo 'obliczanie odleglosci od '$homeCity' do '$cityName ' i porownanie z '$shortCity
    fi

    if [[ $(echo $cityDist'<'$shortDist | bc) -eq 1 ]]
    then
        shortCity=$cityName
    fi
done

#shortCityIdx=$(echo $meteoAPI | jq 'map(.stacja == '\"$shortCity\"') | index(true)')
shortCityIdx=$(echo $meteoAPI | jq --arg shortCity "$shortCity" 'map(.stacja == $shortCity) | index(true)')


echo "najblizsze miasto:" $shortCity
echo "data pomiaru:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].data_pomiaru')
echo "godzina pomiaru:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].godzina_pomiaru')":00"
echo "temperatura:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].temperatura') "C"
echo "predkosc wiatru:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].predkosc_wiatru') "m/s"
echo "kierunek_wiatru:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].kierunek_wiatru')
echo "wilgotnosc wzgledna:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].wilgotnosc_wzgledna') "%"
echo "sumaopadu:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].suma_opadu') "mm"
echo "cisnienie:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].cisnienie') "hPa"