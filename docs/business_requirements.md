# Offline Coding Exercise — Financial Data Ingestion & Canonical Modeling

We receive financial transaction data from multiple customers in different formats (CSV, XML, JSON, TXT). These files often contain data quality issues, such as:

* Duplicate transactions
* Missing or null fields
* Unexpected extra fields
* Negative quantities or amounts
* Inconsistent nesting structures

Your task is to simulate how you would ingest these files into Snowflake.

## Your Assignment

You are provided with four sample files:

* A complex, nested XML file
* A nested JSON file
* A CSV file
* A textf file

Each file contains intentional anomalies.

## What you need to do

* Ingest each file into Snowflake from Azure Blob Storage.
* Design a canonical data model that can represent all three clients’ data.
* Transform the raw data into the canonical structure.
* Identify and handle anomalies (duplicates, nulls, invalid values, etc).