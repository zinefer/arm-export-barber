# ARM Export Trimmer

This is a CLI tool that attempts to interactively assist in parameterizing the Azure Resource IDs out of exported ARM templates. This tool was created mostly to tame [Azure Dashboard exports](https://docs.microsoft.com/en-us/azure/azure-portal/azure-portal-dashboards-create-programmatically#programmatically-create-a-dashboard-from-your-template-using-a-template-deployment) as the process is particularly bad, especially when dealing with serialized JSON that includes nested quotes which is often when you're embedding queries into your dashboards/workbooks.

## Usage

```
usage: trim.rb [json_file] [options]
    -rg, --resource-group  resource group name
    -o, --output           output file path

other
    -v, --version          print the version
    -h, --help             print help
```

```
ruby trim.rb exported-dashboard.json -rg my-resource-group -o trimmed-dashboard.json
```