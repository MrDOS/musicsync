#! /bin/bash

SCRIPT_DIR="$(dirname "$0")"
# Require user confirmation if we're about to try to remove more than this many
# files from the target.
REMOVE_LIMIT=100
# Notify the user if we end up with more than this many files in the target.
FILE_LIMIT=9999

# Conversion/transcoding operations are run in separate processes by
# parallel(1), so we need to export any variables we want them to access.
export ART_RESOLUTION=182x182
export ART_QUALITY=95
# See the man page for flac(1).
export REPLAYGAIN_CONFIG=6aLn1
export TRANSCODE_NICE=15
export AUDIO_BITRATE=320

remove_lots=0

while getopts f flag
do
    case "$flag" in
    f)
        echo "Warning: Forcing removal of lots of files."
        remove_lots=1
        ;;
    ?)
        exit;
        ;;
    esac
done

shift $(expr $OPTIND - 1)

if [ $# -lt 2 ]
then
    echo "Usage: $0 [-f] lastfm-user source-path target-path" 1>&2
    exit 1
fi

export lastfm_user="$1"
export source_path="$2"/
export target_path="$3"/

echo "Last.FM user: $lastfm_user" 1>&2
echo "Source path: $source_path" 1>&2
echo "Target path: $target_path" 1>&2

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
    convert "$source_filename" \
            -resize $ART_RESOLUTION \
            -quality $ART_QUALITY \
            "$target_filename"
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
                 --apply-replaygain-which-is-not-lossless=$REPLAYGAIN_CONFIG \
                 "$source_filename" \
                | nice -n $TRANSCODE_NICE lame \
                    -b $AUDIO_BITRATE \
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
                 --apply-replaygain-which-is-not-lossless=$REPLAYGAIN_CONFIG \
                 "$source_filename" \
                | nice -n $TRANSCODE_NICE lame \
                    -b $AUDIO_BITRATE \
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
    >remove.txt

remove_count=$(wc -l remove.txt | cut -d ' ' -f 1)

if [ $remove_count -ge $REMOVE_LIMIT ]
then
    if [ $remove_lots -eq 1 ]
    then
        cat <<WARN 1>&2
Warning: This operation will remove $remove_count files from the target.
WARN
    else
        cat <<WARN 1>&2
Error: This operation will remove $remove_count files from the target. If
you're sure you want to do this, re-run the script with the -f option.
WARN
        exit 1
    fi
fi

<remove.txt xargs -d '\n' -r rm
rm remove.txt

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
find "$target_path" -type d \
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
    cat <<WARN 1>&2
Warning: $source_file_count songs found in the source, but the destination
supports only up to $FILE_LIMIT files.
WARN
fi

rm artist_names.txt \
   artist_paths.txt \
   source_files.txt \
   target_files.txt

echo "Done."
