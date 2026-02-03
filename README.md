# HelloID-Conn-Prov-Source-C-Quential

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

> [!WARNING]
> As this connector is not yet fully completed, a test environment is required to finalize development and validation. See also: [current state](#current-state)

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Source-C-Quential](#helloid-conn-prov-source-c-quential)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
    - [Functional requirements:](#functional-requirements)
  - [Current state](#current-state)
    - [persons.p1](#personsp1)
      - [Logic](#logic)
    - [departments.ps1](#departmentsps1)
    - [mapping.json](#mappingjson)
    - [`Invoke-CQuentialRestMethod` function](#invoke-cquentialrestmethod-function)
    - [`Resolve-CQuentialError` function](#resolve-cquentialerror-function)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
  - [Remarks](#remarks)
    - [Shifts](#shifts)
    - [Resources](#resources)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Source-C-Quential_ is a _Source_ connector. _C-Quential_ provides a set of REST API's that allow you to programmatically interact with its data. This connector is based on our other roster integrations.

### Functional requirements:

- Create a person record with underlying contracts based on roster rules. Roster rules contain, among others:
- Unique ID of the roster rule (shift) — used as the ContractID in HelloID
- Job function (ID and name)
- Department / cost center (ID and name)
- Start and end date
- Employment sequence number

## Current state

This connector is currently under development and not yet fully completed. The following components have the status described below:

### persons.p1
Currently, the person.ps1 script has been completed, with the remark that the date range filtering did not work at the customer environment. This will need to be validated during implementation.

#### Logic

1. **Date Range Calculation**
   - Determines the import period based on configurable historical and future days.
   - Converts the dates to UTC and URL-encodes them for API requests.

2. **Authentication**
   - Uses API credentials (`UserName`, `Password`, `ClientId`, `ClientSecret`) to request a bearer token.

3. **Retrieve Shifts (Contracts)**
   - Calls the `data-sets/shifts` endpoint with the calculated date range.
   - API returns a table-like structure: one array for field names, another for values.
   - Combines these arrays into a list of structured shift objects for easy searching.

4. **Retrieve Resources and Employments**
   - Calls the `resources` endpoint, including employment data.
   - Groups all resources by `UserId`.

5. **Build Person Objects**
   - For each user, creates a `personObject` containing:
     - User ID, display name, external ID
     - Associated resources and employment records

6. **Generate Contract Objects**
   - For each employment, creates a contract object using the employee number.
   - Associates all relevant shifts with the contract.
   - Attaches the contract objects to the `personObject`.

7. **Output**
   - Converts the fully constructed `personObject` (with all contracts and shifts) to JSON.

### departments.ps1

This feature/component has not been developed as of yet.

### mapping.json

This feature/component has not been developed as of yet.

### `Invoke-CQuentialRestMethod` function

This function is a helper for calling the C-Quential API. It currently performs a simple GET request using the provided URI and headers, and returns the API response.

>[!NOTE]
> The function is **not fully finished**. It exists primarily to centralize API calls, but it does **not yet handle paging**. Paging may be necessary for endpoints that return large datasets, so this function might need to be extended in the future to support that.

### `Resolve-CQuentialError` function

This function is intended to handle and interpret errors returned by the C-Quential API.

> [!NOTE]
> The function is **not fully finished** because the code has not yet been fully tested. Additional validation and error handling may be required before it can be used reliably in production.

## Getting started

### Prerequisites

As this connector is not yet fully completed, a test environment is required to finalize development and validation.

### Connection settings

The following settings are required to connect to the API.

| Setting        | Description                                                             | Mandatory |
| -------------- | ----------------------------------------------------------------------- | --------- |
| UserName       | The username used to connect to the API                                 | Yes       |
| Password       | The password used to connect to the API                                 | Yes       |
| ClientId       | The client ID for API authentication                                    | Yes       |
| ClientSecret   | The client secret for API authentication                                | Yes       |
| BaseUrl        | The base URL of the API                                                 | Yes       |
| HistoricalDays | The number of days in the past from which the shifts will be imported   | Yes       |
| FutureDays     | The number of days in the future from which the shifts will be imported | Yes       |

## Remarks

### Shifts

The response send back from the `/data-sets/shifts?` is structured like a table rather than a list of objects and contains:

- fields
  An array describing each column (field name/caption)
- result.rows
  An array of rows, where each row is an array of values

In order to create a 'normal' shift object, each row is converted to a structured object using the folowing code:

```powershell
foreach ($row in $rawDatashifts.data.result.rows) {
    $shift = @{}
    for ($i = 0; $i -lt $rawDatashifts.data.fields.Count; $i++) {
        $shift[$rawDatashifts.data.fields[$i].caption] = $row[$i]
    }
    $shifts.Add([PSCustomObject]$shift)
}
```

### Resources

The resource contains the raw person data (e.g., firstName, userId) along with employment information. A single person can have multiple resources, each linked to a different employment. The userId remains the same across all resources for a given person. Each resource contains an employeeNumber in the format: 1234/1 or 1234/2. The resources will ultimately result in a contract object.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                    | Description                                                                  |
| ------------------------------------------- | ---------------------------------------------------------------------------- |
| `GET /v3/resources`                         | Retrieves resources (optionally including Employment data)                   |
| `GET /v3/employments`                       | Retrieves employments (optionally including Resource and User data)          |
| `GET /v3/data-sets/shifts/result`           | Retrieves shifts (contracts) filtered by `shownBeginDate` and `shownEndDate` |
| `GET /v3/hr-data-sync/organisational-units` | Retrieves organizational units for HR data synchronization                   |

### API documentation

API documentation is not available publicly and is only accessible to authenticated users.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/Source-systems/powershell-v2-Source-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
