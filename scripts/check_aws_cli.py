import subprocess

def check_aws_cli():
    try:
        result = subprocess.run(['aws','--version'],capture_output = True,text=True,check=True)
        print("AWS CLI is installed:",result.stdout)

    except FileNotFoundError:
        print("AWS CLI is not installed.install it using 'pip install awscli' or your package manager.")

    except subprocess.CalledProcessError as e:
        print("Error checking AWS CLI version:")
        print(e.stderr)


if __name__=="__main__":
    check_aws_cli()                
