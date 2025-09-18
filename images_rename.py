import  os  

dir   = "screenshots"
print("Original files in directory:", os.listdir(dir))
for i, filename in enumerate(os.listdir(dir)):
    os.rename(os.path.join(dir, filename), os.path.join(dir, f"{i}.jpg"))
    print(f"Renamed {filename} to {i}.jpg")
print("Renaming files in directory:", os.listdir(dir))