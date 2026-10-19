// keycode/inspect の結果のとっておき。同じ表記は 1 回だけ聞く（参照先は保存済みのプロファイルで決まるので、snapshot が変わったら捨てる）。
import type { CandidateContext, InspectResult } from '../protocol';
import type { HostClient } from './hostClient';

export class Inspector {
  private readonly results = new Map<string, InspectResult>();
  private readonly inflight = new Map<string, Promise<InspectResult>>();
  private generation = 0;

  constructor(private readonly host: HostClient) {}

  /** とってある結果（なければ undefined） */
  get(context: CandidateContext, text: string): InspectResult | undefined {
    return this.results.get(key(context, text));
  }

  load(context: CandidateContext, text: string): Promise<InspectResult> {
    const k = key(context, text);
    const done = this.results.get(k);
    if (done) return Promise.resolve(done);
    const running = this.inflight.get(k);
    if (running) return running;
    const generation = this.generation;
    const promise = this.host.request('keycode/inspect', { context, text }).then(
      (result) => {
        if (generation === this.generation) this.results.set(k, result);
        this.inflight.delete(k);
        return result;
      },
      (error: unknown) => {
        this.inflight.delete(k);
        throw error;
      },
    );
    this.inflight.set(k, promise);
    return promise;
  }

  clear(): void {
    this.generation++;
    this.results.clear();
    this.inflight.clear();
  }
}

function key(context: CandidateContext, text: string): string {
  return `${context}\u0000${text}`;
}
