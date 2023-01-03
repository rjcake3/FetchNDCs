# FetchNDCs
Powershell script designed to return NDC information from RxNav and openFDA web services when passed a drug name or Anatomical Therapeutic Chemical (ATC) class name
Usage: 

Ex 1: FetchNDCs.ps1 -ATCClass "beta blocking agents" -CSVOut .\betablockerNDCs.csv
Example 1 retrieves medications and their NDCs for beta blocking agents and writes them to the CSV file "betablockerNDCs.csv".

Ex 2: FetchNDCs.ps1 -DrugName metoprolol -CSVOut .\metoprololNDCs.csv
Example 2 retrieves NDCs for generic drug name metoprolol and writes them to "metoprololNDCs.csv".

Ex 3: FetchNDCs.ps1 -DrugName metoprolol 
Example 3 writes the output to the console as a formatted table.   

For other details, type "Get-Help .\FetchNDCs.ps1" at the Powershell command line. 
