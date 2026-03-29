# Serverless Function with AWS Lambda and API Gateway:

Overview
This project demonstrates creating and testing an AWS Lambda function using Node.js, 
monitoring it through CloudWatch, and optionally exposing it via an API Gateway HTTP endpoint.

    Test event (Console / curl)
            |
            v
    AWS Lambda (SimpleLambdaFunction)
            |
            |-- index.js         Basic handler
            |-- index-api.js     API Gateway handler with query parameters
            |
            v
    CloudWatch Logs (/aws/lambda/SimpleLambdaFunction)
            |
            v (optional)
    API Gateway HTTP API
      https://xxx.execute-api.your-region.amazonaws.com/default/SimpleLambdaFunction

## Project Structure:

    Serverless-Function-with-AWS-Lambda-and-API-Gateway/
    |
    |-- index.js            # Basic Lambda handler
    |-- index-api.js        # Enhanced handler with API Gateway support
    |-- test-event.json     # Sample test event payload
    |
    |-- README.md

### Task 1 — Create Lambda Function:

    AWS Console → Lambda → Create function
    
      Option:         Author from scratch
      Function name:  SimpleLambdaFunction
      Runtime:        Node.js 18.x
      Architecture:   x86_64
    
      Execution role: Create a new role with basic Lambda permissions
                      (automatically grants CloudWatch Logs access)
    
    → Create function

### Task 2 — Write and Deploy Code:

    Open the Code tab in the Lambda console, paste the contents of index.js, then click Deploy.
    A "Changes deployed" confirmation message confirms the deployment succeeded.

### Task 3 — Test the Function:

    Lambda Console → Test tab → Create new test event
    
      Event name: TestEvent
      Event JSON: (paste test-event.json contents)

    → Test

    Expected response:
    json{
      "statusCode": 200,
      "body": "\"Hello from Lambda!\""
    }

### Task 4 — Monitor with CloudWatch:

    View Logs
    AWS Console → CloudWatch → Logs → Log groups
    → /aws/lambda/SimpleLambdaFunction
    → Latest log stream

### Task 5 (Optional) — Add API Gateway Trigger:

    Add Trigger
    Lambda Console → Configuration → Triggers → Add trigger
    
      Trigger:   API Gateway
      API type:  HTTP API
      Security:  Open

    → Add → Save
    An endpoint URL will be generated:
    https://xxx.execute-api.your-region.amazonaws.com/default/SimpleLambdaFunction
    Test via curl
    bashAPI_URL="https://xxx.execute-api.your-region.amazonaws.com/default/SimpleLambdaFunction"

    # Basic test
    curl $API_URL
    
    # With query parameter
    curl "$API_URL?name=Ali"
    # Response: {"message":"Hello, Ali from Lambda!","timestamp":"2026-03-28..."}
    Deploy Enhanced Handler
    Replace the Lambda code with the contents of index-api.js and click Deploy.
    This version reads the ?name= query parameter from the URL and returns a dynamic greeting.

### Cleanup:

    Delete Lambda function
    aws lambda delete-function \
      --function-name SimpleLambdaFunction
    
    # Delete API Gateway (via console)
    # API Gateway → APIs → select the API → Delete
    
    # Delete IAM role
    aws iam detach-role-policy \
      --role-name LambdaBasicRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam delete-role \
      --role-name LambdaBasicRole
    
    # Delete CloudWatch log group (optional)
    aws logs delete-log-group \
      --log-group-name /aws/lambda/SimpleLambdaFunction

### License:

    MIT License
