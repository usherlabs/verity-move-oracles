import env from "@/env";
import axios from "axios";

export async function fetchTwitterData(url: string) {
  try {
    const response = await axios.get(url, {
      headers: {
        Authorization: `Bearer ${env.integrations.xBearerToken}`,
        "Content-Type": "application/json",
      },
    });

    return {
      status: response.status,
      message: JSON.stringify(response.data),
    };
  } catch (error) {
    if (axios.isAxiosError(error)) {
      return {
        status: error.response?.status || 500,
        message: JSON.stringify(error.response?.data || { error: "Twitter API request failed" }),
      };
    }
    throw error;
  }
}
