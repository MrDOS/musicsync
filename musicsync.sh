#! /bin/bash

SCRIPT_DIR="$(dirname "$0")"
FILE_LIMIT=9999

if [ $# -lt 2 ]
then
    echo "Usage: $0 lastfm-user source-path target-path" 1>&2
    exit 1
fi

export lastfm_user="$1"
export source_path="$2"/
export target_path="$3"/

if [ ! -d "$source_path" -o ! -r "$source_path" ]
then
    echo "$0: \"$source_path\" is not a directory or is not readable!" 1>&2
    exit 1
fi

if [ ! -d "$target_path" -o ! -w "$target_path" ]
then
    echo "$0: \"$target_path\" is not a directory or is not writable!" 1>&2
    exit 1
fi

echo "Transcoding from \"$2\" to \"$3\"."

echo "Polling Last.FM for artists..."
if ! "$SCRIPT_DIR"/poll.py "$lastfm_user" >artist_names.txt
then
    exit 1
fi

if [ -r always_artists.txt ]
then
    echo "Including additional artists..."
    cat always_artists.txt >>artist_names.txt
fi

echo "Finding matching artists in source..."
if ! "$SCRIPT_DIR"/find.py "$source_path" <artist_names.txt \
    | sort \
    | uniq \
    >artist_paths.txt
then
    exit 1
fi

echo "Scanning source..."
source_path_escaped="$(echo "$source_path" | sed -e 's/\//\\\//g')"
cat artist_paths.txt | while read artist_path
do
    find "$artist_path" -name '*.flac' -o -name '*.mp3'
done \
    | sed -e 's/\.[0-9a-z]\+$//' \
          -e 's/^'"$source_path_escaped"'//' \
    | sort \
    >source_files.txt

echo "Scanning target..."
target_path_escaped="$(echo "$target_path" | sed -e 's/\//\\\//g')"
find "$target_path" -name '*.mp3' \
    | sed -e 's/\.[0-9a-z]\+$//' \
          -e 's/^'"$target_path_escaped"'//' \
    | sort \
    >target_files.txt

convert_art ()
{
    folder_base="$1"
    source_filename=("$source_path"/"$folder_base"/folder.*)
    target_filename="$target_path"/"$(echo "$folder_base" | sed -e 's/^The \([^\/]\+\)/\1, The/' -e 's/[^A-Za-z0-9]*\([A-Za-z0-9]\).*/\u\1\/\0/')"/folder.jpg

    if [ ! -r "$source_filename" ]
    then
        echo "No artwork available for $folder_base."
        return
    fi

    mkdir -p "$(dirname "$target_filename")"
    convert "$source_filename" -resize 180x180 -quality 92 "$target_filename"
    echo "Converted $source_filename → $target_filename."
}
export -f convert_art

transcode ()
{
    filename_base="$1"
    source_filename=("$source_path"/"$filename_base".*)
    target_filename="$target_path"/"$(echo "$filename_base" | sed -e 's/^The \([^\/]\+\)/\1, The/' -e 's/[^A-Za-z0-9]*\([A-Za-z0-9]\).*/\u\1\/\0/')".mp3
    artwork_filename="$(dirname "$target_filename")"/folder.jpg

    mkdir -p "$(dirname "$target_filename")"

    if [[ "$source_filename" == *.mp3 ]]
    then
        cp -v "$source_filename" "$target_filename"
    else
        # Gross.
        eval "$(metaflac --export-tags-to - "$source_filename" | sed -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/=/="/' -e 's/$/"/')"

        if [ -r "$artwork_filename" ]
        then
            flac -dc \
                 --apply-replaygain-which-is-not-lossless "$source_filename" \
                | nice -n 15 lame \
                    -b 320 \
                    --tt "$TITLE" \
                    --ta "$ARTIST" \
                    --tl "$ALBUM" \
                    --ty "$DATE" \
                    --tn "$TRACKNUMBER" \
                    --tg "$GENRE" \
                    --ti "$artwork_filename" \
                    - \
                    "$target_filename"
        else
            flac -dc \
                 --apply-replaygain-which-is-not-lossless "$source_filename" \
                | nice -n 15 lame \
                    -b 320 \
                    --tt "$TITLE" \
                    --ta "$ARTIST" \
                    --tl "$ALBUM" \
                    --ty "$DATE" \
                    --tn "$TRACKNUMBER" \
                    --tg "$GENRE" \
                    - \
                    "$target_filename"
        fi
    fi
    touch -r "$source_filename" "$target_filename"
}
export -f transcode

echo "Removing old music..."
sed -e 's/^The \([^\/]\+\)/\1, The/' \
    -e 's/[^A-Za-z0-9]*\([A-Za-z0-9]\).*/\u\1\/\0/' <source_files.txt \
    | sort \
    | diff --unchanged-line-format= --old-line-format= --new-line-format='%L' - target_files.txt \
    | sed -e 's/^/'"$target_path_escaped"'/' \
          -e 's/$/.mp3/' \
    | xargs -d '\n' -r rm

echo "Converting cover art..."
sed -e 's/.\///' \
    -e 's/\([^\/]\+\), The\//The \1\//' <target_files.txt \
    | sort \
    | diff --unchanged-line-format= --old-line-format='%L' --new-line-format= source_files.txt - \
    | tr '\n' '\0' \
    | xargs -0 dirname \
    | uniq \
    | parallel convert_art

echo "Transcoding new music..."
sed -e 's/.\///' \
    -e 's/\([^\/]\+\), The\//The \1\//' <target_files.txt \
    | sort \
    | diff --unchanged-line-format= --old-line-format='%L' --new-line-format= source_files.txt - \
    | parallel transcode

# The head unit will only pay attention to the first 9,999 files it finds so we
# remove album art after transcoding to keep the file count down.
echo "Removing album art files..."
find "$target_path" -name '*.jpg' -print0 | xargs -0 rm

echo "Removing empty directories..."
find /media/usb0/Music -type d \
    | tac \
    | xargs -d '\n' rmdir --ignore-fail-on-non-empty

echo "Fixing directory modification dates..."
find "$target_path" -type d \
    | sort \
    | tac \
    | while read dir
do
    touch -r "$dir"/"$(ls -1t "$dir" | head -n 1)" "$dir"
done

source_file_count=$(wc -l source_files.txt | cut -d ' ' -f 1)
if [ $source_file_count -gt $FILE_LIMIT ]
then
    echo "Warning: $source_file_count songs found in the source, but the destination supports only up to $FILE_LIMIT files."
fi

rm artist_names.txt \
   artist_paths.txt \
   source_files.txt \
   target_files.txt

echo "Done."
