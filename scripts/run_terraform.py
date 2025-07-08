import subprocess


commands = [
    ["terraform","init"],
    ["terraform","plan"],
    ["terraform","apply","-auto-approve"]
]

def run_terraform_automation_commands(commands):
    for cmd in commands:
        print(f"\n Running: {' '.join(cmd)}")
        try:
            subprocess.run(cmd,check=True)
        except subprocess.CalledProcessError as e:
            print("terraform command failed:",e)
            break

if __name__ == "__main__":
    run_terraform_automation_commands(commands)            
