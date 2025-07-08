import subprocess
import json


def parse_terraform_output():
    try:
        result = subprocess.run(
            ["terraform", "output","-json"],
            capture_output=True,
            text=True,
            check=True
            )
        return json.loads(result.stdout)
    
    except subprocess.CalledProcessError as e:
        print("Error running terraform output command:", e)
        return None
    

def save_to_file(data,filename="tf_output.json"):
    with open(filename,"w") as f:
        json.dump(data,f,indent=2)
    print(f"Ouput saved to {filename}")       

if __name__ =="__main__":
    output = parse_terraform_output()
    save_to_file(output)    
        
