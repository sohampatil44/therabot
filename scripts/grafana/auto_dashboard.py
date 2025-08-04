import requests
import json
import time

GRAFANA_URL = "http://localhost:3000"
USERNAME = "admin"
PASSWORD = "admin"

def waitforgrafana():
    for _ in range(20):
        try:
            res = requests.get(f"{GRAFANA_URL}/api/health")
            if res.status_code == 200:
                print("Grafana is up")
                return

        except Exception:
            pass
        time.sleep(5)

    raise Exception("Grafana did not start in time")


def setpassword():
    print("setting credentials for grafana...")

    requests.put(
        f"{GRAFANA_URL}/api/admin/passwords",
        auth = (USERNAME,PASSWORD),
        json={"password":PASSWORD}
    )

def add_cloudwatch_datasource():
    print("Adding cloudwatch data source...")
    data = {
        "name" : "Cloudwatch",
        "type" : "cloudwatch",
        "access" : "proxy",
        "jsonData" : {
            "authType":"ec2_iam_role",
            "defaultRegion": "us-east-1"
        }
    }    

    res = requests.post(
        f"{GRAFANA_URL}/api/datasources",
        auth = (USERNAME,PASSWORD),
        json = data
    )

    print("CloudWatch data source added:", res.status_code)



def main():
    waitforgrafana()
    setpassword()
    add_cloudwatch_datasource()

    #getting instance id dynamically using metadata

    try:
        res = requests.get("http://169.254.169.254/latest/meta-data/instance-id", timeout=2)
        if res.status_code == 200:
            instance_id = res.text
        else:
            instance_id = "i-xxxxxxxxxxxxxx"
    except Exception:
        instance_id = "i-xxxxxxxxxxxxxx"


    with open('/home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/ec2-dashboard.json','r') as f:
        dashboard = json.load(f)

    dashboard['title']  = f"EC2 Dashboard - {instance_id}"

    dashboard_data = {
        "dashboard": dashboard,
        "overwrite": True
    }    

    res = requests.post(
        f"{GRAFANA_URL}/api/dashboards/db",
        auth=(USERNAME,PASSWORD),
        json=dashboard_data
    )  

    print("Dashboard uploaded:",res.status_code)

if __name__ == "__main__":
    main()               

            