import type { ProviderId } from "../../providers/contracts";
import {
  getBflCredits,
  pollBflGeneration,
  submitBflGeneration,
} from "./bfl";

export const serverProviders = {
  bfl: {
    submit: submitBflGeneration,
    poll: pollBflGeneration,
    credits: getBflCredits,
  },
} satisfies Record<ProviderId, unknown>;

export function getServerProvider(provider: ProviderId) {
  return serverProviders[provider];
}
