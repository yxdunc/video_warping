#!/bin/bash

# Set the paths and filenames
input_video="${HOME}/Downloads/dome.mp4"
temp_dir="/tmp/warp__001"
output_video="warped_dome.mp4"
warp_tool="${HOME}/Downloads/tgawarp_july2022/jpgwarp"
warp_map="${HOME}/Downloads/xyuv.data"
concat_list="/tmp/concat_list.txt"

# Frame extraction settings
chunk_size=1000  # Number of frames to process in one go

# Get video duration and frame rate using ffprobe
video_duration=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nokey=1:noprint_wrappers=1 "$input_video")
frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nokey=1:noprint_wrappers=1 "$input_video" | awk -F'/' '{if ($2 == "") print $1; else print $1/$2}')
total_frames=$(bc <<< "$video_duration * $frame_rate / 1")  # Convert to integer

echo "Video duration: $video_duration seconds"
echo "Frame rate: $frame_rate frames per second"
echo "Total frames: $total_frames"

echo "You most likely want to make sure $temp_dir is empty before running this script"

# Create temporary directory if it doesn't exist
mkdir -p "$temp_dir"

# Initialize the concat list file
echo "" > $concat_list

# Process frames in chunks
for ((start_frame=0; start_frame<total_frames; start_frame+=chunk_size)); do
    end_frame=$((start_frame + chunk_size - 1))
    echo "Processing frames from $start_frame to $end_frame"

    # Calculate the start time in seconds with 2 decimal precision
    start_time=$(printf "%.2f" "$(bc <<< "scale=2; $start_frame / $frame_rate")")

    # Extract the exact number of frames needed
    ffmpeg -hide_banner -loglevel error -ss "$start_time" -i "$input_video" -frames:v $chunk_size -vf "setpts=PTS-STARTPTS" -an -q:v 0 "$temp_dir/warping_%05d.tga"

    # Check if frames were extracted
    if ls "$temp_dir/warping_"*.tga 1> /dev/null 2>&1; then
        echo "Frames extracted successfully: $(ls "$temp_dir/warping_"*.tga | wc -l)"

        # Apply warp filter to the extracted frames
        "$warp_tool" -w 1920 -a 3 -n 1 -o "$temp_dir/warped_%05d.tga" "$temp_dir/warping_%05d.tga" "$warp_map"

        # Check if warp tool succeeded
        if [ $? -ne 0 ]; then
            echo "Error: Failed to apply warp filter with $warp_tool"
            exit 1
        fi

        # Check if warped frames were generated
        if ls "$temp_dir/warped_"*.tga 1> /dev/null 2>&1; then
            echo "Warped frames generated successfully: $(ls "$temp_dir/warped_"*.tga | wc -l)"

            # Clean up the original extracted frames to save disk space
            rm "$temp_dir/warping_"*.tga

            # Encode the warped frames back to video (append to the final video)
            ffmpeg -hide_banner -loglevel error -framerate "$frame_rate" -i "$temp_dir/warped_%05d.tga" -c:v libx264 -pix_fmt yuv420p -r "$frame_rate" "${temp_dir}/warped_chunk_${start_frame}.mp4"

            # Check if encoding succeeded
            if [ $? -ne 0 ]; then
                echo "Error: Failed to encode warped frames with ffmpeg"
                exit 1
            fi

            # Add the chunk to the concat list
            echo "file '${temp_dir}/warped_chunk_${start_frame}.mp4'" >> $concat_list

            # Clean up warped frames
            rm "$temp_dir/warped_"*.tga
        else
            echo "Error: No warped frames generated for range $start_frame to $end_frame"
            exit 1
        fi
    else
        echo "Error: No frames extracted for range $start_frame to $end_frame"
        exit 1
    fi
done

# Concatenate all chunks into the final video
ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i $concat_list -c copy "$output_video"

# Check if concatenation succeeded
if [ $? -ne 0 ]; then
    echo "Error: Failed to concatenate video chunks with ffmpeg"
    exit 1
fi

# Clean up temporary files
rm -rf "$temp_dir"
rm $concat_list

echo "Warping process complete. Output video saved as $output_video."

