import os
import numpy as np

def compute_statistics(file_path):
    try:
        with open(file_path, 'r') as file:
            numbers = [float(line.strip()) for line in file]
        mean = np.mean(numbers)
        stddev = np.std(numbers)
        return mean, stddev
    except Exception as e:
        print(f"Error processing file {file_path}: {e}")
        return None, None

def process_folder(folder_path):
    for filename in os.listdir(folder_path):
        file_path = os.path.join(folder_path, filename)
        mean, stddev = compute_statistics(file_path)
        print(f"File: {filename}, Mean: {mean}, Stdev: {stddev}")

if __name__ == "__main__":
    folder_path = 'stats/time/' 
    process_folder(folder_path)
