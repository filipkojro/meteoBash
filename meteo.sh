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

if ! [[ -e "$HOME/.meteorc" ]] # sprawdzenie pliku konfiguracyjnego lub stworzenie go z podstawowymi wartosciami
then
    echo 'No cache file'
    echo '{"cashpath":"'"$HOME"'/.cache/meteo/"}' > "$HOME/.meteorc"
    mkdir -p "$HOME/.cache/meteo/"
fi

cashPath=$(cat "$HOME/.meteorc" | jq -r '.cashpath')

if [[ $debug -eq 1 ]]
then
echo 'pobieranie danych z IMGW'
fi

if [[ -e $cashPath'meteoCash.json' && -e $cashPath'meteoCash.txt' ]] # pobieranie danych z IMGW tylko gdy dane sa starsze niz godzina lub gdy ich nie ma
then
    meteoAPI=$(cat $cashPath'meteoCash.json')
    if [[ "$(echo $meteoAPI | jq -r '.[0].data_pomiaru')$(echo $meteoAPI | jq -r '.[0].godzina_pomiaru')" != "$(cat $cashPath'meteoCash.txt')" ]]
    then
        meteoAPI=$(curl -s https://danepubliczne.imgw.pl/api/data/synop) # pobieranie danych od IMGW-PIB
        echo $meteoAPI > $cashPath'meteoCash.json'
        echo "$(echo $meteoAPI | jq -r '.[0].data_pomiaru')$(echo $meteoAPI | jq -r '.[0].godzina_pomiaru')" > $cashPath'meteoCash.txt'
    fi
else
    meteoAPI=$(curl -s https://danepubliczne.imgw.pl/api/data/synop) # pobieranie danych od IMGW-PIB
    echo $meteoAPI > $cashPath'meteoCash.json'
    echo "$(echo $meteoAPI | jq -r '.[0].data_pomiaru')$(echo $meteoAPI | jq -r '.[0].godzina_pomiaru')" > $cashPath'meteoCash.txt'
fi



if test -e $cashPath'cityCash.json';
then
    cityCash=$(cat $cashPath'cityCash.json')
else
    echo 'pierwsze uruchomienie potrwa ponad minute z powodu ograniczen nalozonych przez https://nominatim.org/'
    echo 'prosze o cierpliwosc :)'
    echo {} > $cashPath'cityCash.json'
fi

# pobieranie danych z api nominatim
for ((i=0; i<=$(echo $meteoAPI | jq '. | length'); i++));
do
    echo -n '*'
    if [[ $i -eq $(echo $meteoAPI | jq '. | length') ]]
    then
        cityName=$1
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

        if [[ -z "$cityGeometry" || "$cityGeometry" == "null" ]] # dodawanie do cachu
        then
            echo "Error while fetching data from Nominatim for $cityName"
            exit 1
        else
            echo $cityGeometry > temp.json
            echo $(jq --argfile cityGeometry temp.json '.'$cityName' += $cityGeometry' $cashPath'cityCash.json') > $cashPath'cityCash.json'
            rm temp.json
        fi
        sleep 1 # nominatim przyjmuje max 1 zapytanie na 1s
    fi
done

echo ' '
homeCity=$(echo $homeCity | iconv -f utf8 -t ascii//TRANSLIT) #usuwanie polskich znakow z nazwy miasta
homeCity=$(echo $homeCity | tr ' ' '_') #usuwanie spacji z nazwy miasta

inputx=$(cat $cashPath'cityCash.json' | jq '.'$homeCity'.coordinates[0]')
inputy=$(cat $cashPath'cityCash.json' | jq '.'$homeCity'.coordinates[1]')

shortCity=$(echo $meteoAPI | jq -r '.[0].stacja')

for ((i=0; i<$(echo $meteoAPI | jq '. | length'); i++)); # ustalenie najblizszego miasta
do
    echo -n '*'
    shortCityPars=$(echo $shortCity | iconv -f utf8 -t ascii//TRANSLIT | tr ' ' '_') #usuwanie polskich znakow i spacji z nazwy miasta
    shortx=$(cat $cashPath'cityCash.json' | jq '.'$shortCityPars'.coordinates[0]')
    shorty=$(cat $cashPath'cityCash.json' | jq '.'$shortCityPars'.coordinates[1]')

    # obliczanie odleglosci od poprzedniego najblizszego miasta
    deltax=$(echo $inputx-$shortx | bc)
    deltay=$(echo $inputy-$shorty | bc)
    shortDist=$(echo $deltax*$deltax+$deltay*$deltay | bc) # obliczanie odleglosci korzystajac z twierdzenie pitagorasa

    cityName=$(echo $meteoAPI | jq -r '.['$i'].stacja')
    cityNamePars=$(echo $cityName | iconv -f utf8 -t ascii//TRANSLIT | tr ' ' '_') #usuwanie polskich znakow i spacji z nazwy miasta
    
    cityx=$(cat $cashPath'cityCash.json' | jq '.'$cityNamePars'.coordinates[0]')
    cityy=$(cat $cashPath'cityCash.json' | jq '.'$cityNamePars'.coordinates[1]')

    # obliczanie odleglosci od miasta
    deltax=$(echo $inputx-$cityx | bc)
    deltay=$(echo $inputy-$cityy | bc)
    cityDist=$(echo $deltax*$deltax+$deltay*$deltay | bc) # obliczanie odleglosci korzystajac z twierdzenie pitagorasa

    if [[ $debug -eq 1 ]]
    then
    echo 'obliczanie odleglosci od '$homeCity' do '$cityName ' i porownanie z '$shortCity 'odeglosc' $cityDist '<' $shortDist
    fi

    if [[ $(echo "$cityDist < $shortDist" | bc -l) -eq 1 ]] # porownanie odleglosci poprzedniego najblizszego miasta i nowo obliczonego miasta
    then
        shortCity=$cityName
        shortDist=$cityDist
    fi

done

shortCityIdx=$(echo $meteoAPI | jq --arg shortCity "$shortCity" 'map(.stacja == $shortCity) | index(true)')

# wypisanie danych pogodowych najblizszego miasta do wpidanego

echo ' '

echo $shortCity '['$(echo $meteoAPI | jq -r '.['$shortCityIdx'].id_stacji')'] /' $(echo $meteoAPI | jq -r '.['$shortCityIdx'].data_pomiaru') $(echo $meteoAPI | jq -r '.['$shortCityIdx'].godzina_pomiaru')":00"
echo "temperatura:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].temperatura') "°C"
echo "predkosc wiatru:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].predkosc_wiatru') "m/s"
echo "kierunek_wiatru:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].kierunek_wiatru') "°"
echo "wilgotnosc wzgledna:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].wilgotnosc_wzgledna') "%"
echo "sumaopadu:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].suma_opadu') "mm"
echo "cisnienie:" $(echo $meteoAPI | jq -r '.['$shortCityIdx'].cisnienie') "hPa"