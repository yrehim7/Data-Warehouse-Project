/*
feat: Implement silver layer loading procedure  

- Created stored procedure `silver.load_silver` for loading data into the Silver layer.  
- Includes data normalization, transformation, and cleanup for CRM, ERP, and sales tables.  
- Implements deduplication, NULL handling, and standardized formatting.  
- Uses error handling to catch and log failures during execution.  
- Prints execution details for monitoring load duration. 

*/
--EXEC silver.load_silver

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY	
		SET @batch_start_time = GETDATE();
		PRINT '============================================';
		PRINT 'Loading Silver Layer';
		PRINT '============================================';


		PRINT '--------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '--------------------------------------------';

		-- Loading silver.crm_cust_info
		SET @start_time = GETDATE();
		PRINT '>> TRUNCATING Table: silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info;
		PRINT '>> Inserting Data Into: silver._cust_info';
		INSERT INTO silver.crm_cust_info (
			cst_id, 
			cst_key, 
			cst_firstname, 
			cst_lastname, 
			cst_material_status, 
			cst_gndr, 
			cst_create_date
		)
		-- Selection of the cleaned and standardized data
		SELECT 
			cst_id, 
			cst_key, 
			TRIM(cst_firstname) AS cst_firstname,  -- Removes unnecessary spaces in the first name
			TRIM(cst_lastname) AS cst_lastname,    -- Removes unnecessary spaces in the last name
			CASE -- Normalize of marital status: S → Single, M → Married, otherwise 'n/a'
				WHEN UPPER(TRIM(cst_material_status)) = 'S' THEN 'Single' 
				WHEN UPPER(TRIM(cst_material_status)) = 'M' THEN 'Married' 
				ELSE 'n/a' 
			END AS cst_material_status,
			CASE -- Normalize of gender: F → Female, M → Male, otherwise 'n/a'
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female' 
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male' 
				ELSE 'n/a' 
			END AS cst_gndr,

			cst_create_date -- Retains the original creation date

		FROM (
			-- Marking duplicate cst_id (only the most recent version is kept)
			SELECT 
				*, 
				ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last 
			FROM bronze.crm_cust_info
		) t 

		WHERE flag_last = 1;  -- Only the most recent records are retained
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds'
		PRINT '>> -----------------------'


		-- Loading silver.crm_erp_info
		SET @start_time = GETDATE();
		PRINT '>> TRUNCATING Table: silver.crm_erp_info';
		TRUNCATE TABLE silver.crm_erp_info;
		PRINT '>> Inserting Data Into: silver.crm_erp_info';
		INSERT INTO silver.crm_erp_info (
			prd_id,
			cat_id,
			prd_key,
			prd_nm,
			prd_cost,
			prd_line,
			prd_start_dt,
			prd_end_dt
		)

		SELECT 
		prd_id,
		REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')  AS cat_id,
		SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
		prd_nm,
		ISNULL(prd_cost, 0) AS prd_cost,
		CASE 
				WHEN prd_line IS NULL THEN 'n/a'  -- Handling NULL values
				WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mobile'
				WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Retail'
				WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Software'
				WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Technology'
				ELSE 'Other'  -- Catch-all for unexpected values
			END AS prd_line,
			-- Ensure prd_start_dt is in proper format
			CAST(prd_start_dt AS DATE) AS prd_start_dt,

			-- Use LEAD to get the next row's prd_start_dt and set it as prd_end_dt
			CAST(
				LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS DATE
			) AS prd_end_dt

		FROM bronze.crm_prd_info;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds'
		PRINT '>> -----------------------'

		-- Loading silver.crm_sales_details
		SET @start_time = GETDATE();
		PRINT '>> TRUNCATING Table: silver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details;
		PRINT '>> Inserting Data Into: silver.crm_sales_details';
		INSERT silver.crm_sales_details (
			sls_order_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price
		)

		SELECT
			sls_order_num,
			sls_prd_key,
			sls_cust_id,
			CASE 
				WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
				ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
			END AS sls_order_dt,
			CASE 
				WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
				ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
			END AS sls_ship_dt,
			CASE 
				WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
				ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
			END AS sls_due_dt,
			CASE 
				WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
					THEN sls_quantity * ABS(sls_price)
				ELSE sls_sales
			END AS sls_sales,
			sls_quantity,
			CASE 
				WHEN sls_price IS NULL OR sls_price <= 0
				THEN sls_sales / NULLIF(sls_quantity, 0)
				ELSE sls_price
			END AS sls_price

		FROM bronze.crm_sales_details;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds'
		PRINT '>> -----------------------'


		-- Loading silver.erp_loc_a101
		SET @start_time = GETDATE();
		PRINT '>> TRUNCATING Table: silver.erp_loc_a101';
		TRUNCATE TABLE silver.erp_loc_a101;
		PRINT '>> Inserting Data Into: silver.erp_loc_a101';
		INSERT INTO silver.erp_loc_a101(
		cid,cntry)
		SELECT
			REPLACE(cid, '-', '') cid,
			CASE
				WHEN TRIM(cntry) = 'DE'  THEN 'Germany'
				WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
				WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
				ELSE TRIM(cntry)
			END as cntry -- Normalize and Handle missing or blank country codes
		FROM bronze.erp_loc_a101;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds'
		PRINT '>> -----------------------'


		-- Loading silver.erp_px_cat_g1v2
		SET @start_time = GETDATE();
		PRINT '>> TRUNCATING Table: silver.erp_px_cat_g1v2';
		TRUNCATE TABLE silver.erp_px_cat_g1v2;
		PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
		INSERT INTO silver.erp_px_cat_g1v2
		(id, cat, subcat, maintenance)
		SELECT
			id,
			cat,
			subcat,
			maintenance
		FROM bronze.erp_px_cat_g1v2;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds'
		PRINT '>> -----------------------'


		-- Loading silver.erp_cust_az12
		SET @start_time = GETDATE();
		PRINT '>> TRUNCATING Table: silver.erp_cust_az12';
		TRUNCATE TABLE silver.erp_cust_az12;
		PRINT '>> Inserting Data Into: silver.erp_cust_az12';
		INSERT INTO silver.erp_cust_az12(
			cid,
			bdate,
			gen
		)
		SELECT
		CASE 
			WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) -- Remove 'NAS' prefix if present
				ELSE cid
		END AS cid,
		CASE WHEN bdate > GETDATE() THEN NULL
			ELSE bdate
		END AS bdate, -- Set future birthdates to NULL
		CASE 
			WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
			WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
			ELSE 'n/a'
		END AS gen -- Normalize gender values and handle unknown cases

		FROM bronze.erp_cust_az12;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds'
		PRINT '>> -----------------------'

		SET @batch_end_time = GETDATE();
		PRINT '==========================================='
		PRINT 'Loading Silver Layer is Completed';
		PRINT '    - Total Load duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds'
		PRINT '==========================================='

	END TRY
		BEGIN CATCH
			PRINT '==========================================='
			PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
			PRINT 'Error Message' + ERROR_MESSAGE();
			PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
			PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
			PRINT '==========================================='
		END CATCH
END
