import time
import os
import shutil

def main():
    # Get current timestamp
    timestr = time.strftime("%Y%m%d-%H%M%S")
    print(timestr)

    # Create log file
    log_file_path = os.path.expanduser(f"~/script-log-{timestr}.log")
    
    def log_error(message):
        with open(log_file_path, 'a') as log_file:
            log_file.write(message + '\n')
    
    try:
        print(f"A log file, named [script-log-{timestr}] for this script is in your home folder")
        print("This script expects input of a plaintext file, and on each line of that file, the script:")
        print("identifies the first occurrence of the forward-slash character \"/\"")
        print("deletes the forward slash")
        print("deletes all other characters on the line after the forward slash character")
        print("outputs the remaining characters on that line to a new file")
        print("the new file output is in same location as the input file, with [.out] added to the end of the filename")

        user_spec_file = input("Please provide input file [/path/to/filename]: ")

        # Variables
        temp_tag = "/.tmp."
        out_tag = ".out"

        # Create temporary file
        temp_tag_user_file_name = os.path.dirname(user_spec_file) + temp_tag + os.path.basename(user_spec_file)
        shutil.copy(user_spec_file, temp_tag_user_file_name)
        
        # Output file
        output_file = user_spec_file + out_tag

        def remove_forward_slash():
            with open(temp_tag_user_file_name, 'r') as infile, open(output_file, 'w') as outfile:
                line_count = 0
                for line in infile:
                    if line_count >= 255:
                        break
                    slash_index = line.find('/')
                    if slash_index != -1:
                        line = line[:slash_index]
                    outfile.write(line.strip() + '\n')
                    line_count += 1

        remove_forward_slash()

        os.remove(temp_tag_user_file_name)
        print("Completed. The output is in the same location as the file you specified as input")

    except Exception as e:
        log_error(str(e))
        print(f"An error occurred. Please check the log file at {log_file_path} for details.")

if __name__ == "__main__":
    main()
