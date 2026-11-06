# Opens the Locust web UI against the local API.
# In the browser: 15 users, spawn rate 3, then Start.
Set-Location $PSScriptRoot\..
& .\.venv\Scripts\python.exe -m locust -f locustfile.py --host http://127.0.0.1:8000
