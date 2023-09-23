import json
import re
import time
import uuid

import boto3


# function definition
def lambda_handler(event, context):
    maillist_id = str(uuid.uuid4())
    data = event.get("queryStringParameters", {}) or {}

    errors = []
    formatted_data = {}
    for key in ("name", "email"):
        if value := data.get(key):
            value = value.strip().lower()
            if key == "email":
                if not re.match(
                    r"([A-Za-z0-9]+[.-_])*[A-Za-z0-9]+@[A-Za-z0-9-]+(\.[A-Z|a-z]{2,})+",
                    value,
                ):
                    errors.append(f"{value} is not a valid email")
            formatted_data[key] = value
        else:
            errors.append(f"[{key}] is has invalid value of <{value}>")

    if errors:
        return {"statusCode": 400, "body": json.dumps(errors)}

    dynamodb = boto3.resource("dynamodb")
    # table name
    table = dynamodb.Table("ntt_maillist")
    fetched = table.get_item(Key={"email": formatted_data["email"]})

    if item := fetched.get("Item"):
        print("item", item)
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "uuid": item["uuid"],
                    "created_at": int(item["created_at"]),
                    "confirmed_at": int(item["confirmed_at"]),
                    "message": "subscription already exists",
                }
            ),
        }

    response = table.put_item(
        Item={
            "uuid": maillist_id,
            "name": formatted_data["name"],
            "email": formatted_data["email"],
            "created_at": int(time.time()),
            "confirmed_at": 0,
        }
    )
    # return response
    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "uuid": maillist_id,
                "name": formatted_data.get("name"),
                "email": formatted_data.get("email"),
            }
        ),
    }
